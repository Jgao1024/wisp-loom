use super::*;
use std::io::{BufReader, Read};
use std::sync::mpsc::Receiver;
use std::time::Instant;

/// stdin stand-in the test can feed line by line; closing the sender is EOF.
struct Feed(Receiver<Vec<u8>>, Vec<u8>);

impl Read for Feed {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        if self.1.is_empty() {
            match self.0.recv() {
                Ok(bytes) => self.1 = bytes,
                Err(_) => return Ok(0),
            }
        }
        let n = buf.len().min(self.1.len());
        buf[..n].copy_from_slice(&self.1[..n]);
        self.1.drain(..n);
        Ok(n)
    }
}

#[derive(Clone, Default)]
struct Sink(Arc<Mutex<Vec<u8>>>);

impl Write for Sink {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        self.0.lock().unwrap().extend_from_slice(buf);
        Ok(buf.len())
    }
    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

struct Session {
    input: std::sync::mpsc::Sender<Vec<u8>>,
    sink: Sink,
    server: thread::JoinHandle<()>,
}

impl Session {
    fn start(backend: Backend) -> Session {
        let (input, rx) = channel();
        let sink = Sink::default();
        let out = sink.clone();
        let server = thread::spawn(move || backend.serve(BufReader::new(Feed(rx, Vec::new())), out));
        Session { input, sink, server }
    }

    fn send(&self, value: Value) {
        self.input.send(format!("{value}\n").into_bytes()).unwrap();
    }

    fn lines(&self) -> Vec<Value> {
        let bytes = self.sink.0.lock().unwrap().clone();
        String::from_utf8(bytes)
            .unwrap()
            .lines()
            .map(|l| serde_json::from_str(l).unwrap())
            .collect()
    }

    fn wait_for(&self, what: &str, done: impl Fn(&[Value]) -> bool) -> Vec<Value> {
        let deadline = Instant::now() + Duration::from_secs(5);
        loop {
            let lines = self.lines();
            if done(&lines) {
                return lines;
            }
            assert!(
                Instant::now() < deadline,
                "timed out waiting for {what}: {lines:?}"
            );
            thread::sleep(Duration::from_millis(5));
        }
    }

    /// Closing stdin ends the loop; returns everything written.
    fn finish(self) -> Vec<Value> {
        drop(self.input);
        self.server.join().unwrap();
        let bytes = self.sink.0.lock().unwrap().clone();
        String::from_utf8(bytes)
            .unwrap()
            .lines()
            .map(|l| serde_json::from_str(l).unwrap())
            .collect()
    }
}

fn has_result(lines: &[Value], id: u64) -> bool {
    lines
        .iter()
        .any(|l| l["id"] == id && (l.get("result").is_some() || l.get("error").is_some()))
}

#[test]
fn request_gets_result_and_event() {
    let session = Session::start(Backend::new().method("echo", |params, ctx| {
        ctx.emit(json!({"type": "progress", "pct": 50}));
        Ok(params)
    }));
    session.send(json!({"id": 1, "method": "echo", "params": {"x": 1}}));
    let lines = session.wait_for("result", |l| has_result(l, 1));
    assert_eq!(
        lines[0],
        json!({"id": 1, "event": {"type": "progress", "pct": 50}})
    );
    assert_eq!(lines[1], json!({"id": 1, "result": {"x": 1}}));
    session.finish();
}

#[test]
fn unknown_method_and_handler_errors() {
    let session =
        Session::start(Backend::new().method("fail", |_, _| Err(Error::new("http_401", "bad key"))));
    session.send(json!({"id": 1, "method": "nope"}));
    session.send(json!({"id": 2, "method": "fail"}));
    let lines = session.wait_for("errors", |l| has_result(l, 1) && has_result(l, 2));
    let error = |id: u64| lines.iter().find(|l| l["id"] == id).unwrap()["error"].clone();
    assert_eq!(error(1)["code"], "method_not_found");
    assert_eq!(error(2), json!({"code": "http_401", "message": "bad key"}));
    session.finish();
}

#[test]
fn panicking_handler_does_not_kill_the_loop() {
    let session = Session::start(
        Backend::new()
            .method("boom", |_, _| panic!("oops"))
            .method("ok", |_, _| Ok(json!("fine"))),
    );
    session.send(json!({"id": 1, "method": "boom"}));
    session.send(json!({"id": 2, "method": "ok"}));
    let lines = session.wait_for("both", |l| has_result(l, 1) && has_result(l, 2));
    assert_eq!(
        lines.iter().find(|l| l["id"] == 1).unwrap()["error"]["code"],
        "internal"
    );
    session.finish();
}

#[test]
fn requests_run_concurrently() {
    let session = Session::start(
        Backend::new()
            .method("slow", |_, ctx| {
                while !ctx.cancelled() {
                    thread::sleep(Duration::from_millis(5));
                }
                Err(Error::cancelled())
            })
            .method("fast", |_, _| Ok(json!("fast"))),
    );
    session.send(json!({"id": 1, "method": "slow"}));
    session.send(json!({"id": 2, "method": "fast"}));
    let lines = session.wait_for("fast result", |l| has_result(l, 2));
    assert!(!has_result(&lines, 1), "slow request must still be running");
    session.send(json!({"method": "cancel", "params": {"id": 1}}));
    let lines = session.wait_for("cancelled", |l| has_result(l, 1));
    let slow = lines.iter().find(|l| l["id"] == 1).unwrap();
    assert_eq!(slow["error"]["code"], "cancelled");
    session.finish();
}

#[test]
fn closing_stdin_cancels_running_requests() {
    let session = Session::start(Backend::new().method("slow", |_, ctx| {
        while !ctx.cancelled() {
            thread::sleep(Duration::from_millis(5));
        }
        Err(Error::cancelled())
    }));
    session.send(json!({"id": 1, "method": "slow"}));
    thread::sleep(Duration::from_millis(50));
    let lines = session.finish();
    assert_eq!(lines.last().unwrap()["error"]["code"], "cancelled");
}

#[test]
fn deltas_are_coalesced_and_ordered_before_the_result() {
    let session = Session::start(Backend::new().method("stream", |_, ctx| {
        for piece in ["a", "b", "c", "d"] {
            ctx.emit(json!({"type": "text_delta", "delta": piece}));
        }
        ctx.emit(json!({"type": "tool_start", "name": "x"}));
        ctx.emit(json!({"type": "text_delta", "delta": "e"}));
        Ok(json!("done"))
    }));
    session.send(json!({"id": 1, "method": "stream"}));
    let lines = session.wait_for("result", |l| has_result(l, 1));
    let events: Vec<Value> = lines.iter().filter_map(|l| l.get("event").cloned()).collect();
    assert_eq!(
        events,
        vec![
            json!({"type": "text_delta", "delta": "abcd"}),
            json!({"type": "tool_start", "name": "x"}),
            json!({"type": "text_delta", "delta": "e"}),
        ]
    );
    assert_eq!(lines.last().unwrap()["result"], "done");
    session.finish();
}

#[test]
fn deltas_flush_on_a_timer_while_the_request_runs() {
    let session = Session::start(Backend::new().method("hold", |_, ctx| {
        ctx.emit(json!({"type": "text_delta", "delta": "hi"}));
        while !ctx.cancelled() {
            thread::sleep(Duration::from_millis(5));
        }
        Ok(Value::Null)
    }));
    session.send(json!({"id": 1, "method": "hold"}));
    session.wait_for("timed flush", |l| l.iter().any(|m| m["event"]["delta"] == "hi"));
    session.finish();
}

#[test]
fn shell_calls_round_trip() {
    let session = Session::start(Backend::new().method("needs_key", |_, ctx| {
        ctx.shell("shell.secret.get", json!({"key": "token"}))
    }));
    session.send(json!({"id": 1, "method": "needs_key"}));
    let lines = session.wait_for("shell request", |l| l.iter().any(|m| m["id"] == "s1"));
    assert_eq!(
        lines[0],
        json!({"id": "s1", "method": "shell.secret.get", "params": {"key": "token"}})
    );
    session.send(json!({"id": "s1", "result": "hunter2"}));
    let lines = session.wait_for("result", |l| has_result(l, 1));
    assert_eq!(lines.last().unwrap()["result"], "hunter2");
    session.finish();
}

#[test]
fn shell_errors_surface_as_errors() {
    let session = Session::start(Backend::new().method("needs_key", |_, ctx| {
        ctx.shell("shell.secret.get", json!({"key": "token"}))
    }));
    session.send(json!({"id": 1, "method": "needs_key"}));
    session.wait_for("shell request", |l| l.iter().any(|m| m["id"] == "s1"));
    session.send(json!({"id": "s1", "error": {"code": "forbidden", "message": "no"}}));
    let lines = session.wait_for("result", |l| has_result(l, 1));
    assert_eq!(lines.last().unwrap()["error"]["code"], "forbidden");
    session.finish();
}
