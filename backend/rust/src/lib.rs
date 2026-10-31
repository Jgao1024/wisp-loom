//! Backend SDK: a stdio JSON Lines loop with one thread per request.
//! Protocol: docs/02-app-protocol.md §3.

use serde::Serialize;
use serde_json::{Value, json};
use std::collections::{HashMap, HashSet};
use std::io::{BufRead, Write};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::mpsc::{Sender, channel};
use std::sync::{Arc, Condvar, Mutex, MutexGuard};
use std::thread;
use std::time::Duration;

/// Same-kind `*_delta` events are merged for this long before being written.
const COALESCE: Duration = Duration::from_millis(16);

#[derive(Debug, Clone, PartialEq)]
pub struct Error {
    pub code: String,
    pub message: String,
}

impl Error {
    pub fn new(code: impl Into<String>, message: impl Into<String>) -> Self {
        Error {
            code: code.into(),
            message: message.into(),
        }
    }

    pub fn cancelled() -> Self {
        Error::new("cancelled", "cancelled")
    }
}

/// Lets handlers use `?` on `serde_json` and `io` errors.
impl<E: std::error::Error> From<E> for Error {
    fn from(error: E) -> Self {
        Error::new("error", error.to_string())
    }
}

type Handler = Arc<dyn Fn(Value, &Ctx) -> Result<Value, Error> + Send + Sync>;

#[derive(Default)]
pub struct Backend {
    methods: HashMap<String, Handler>,
}

impl Backend {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn method<F>(mut self, name: &str, handler: F) -> Self
    where
        F: Fn(Value, &Ctx) -> Result<Value, Error> + Send + Sync + 'static,
    {
        self.methods.insert(name.to_string(), Arc::new(handler));
        self
    }

    /// Serves stdin/stdout until stdin closes, then waits for running requests.
    pub fn run(self) {
        self.serve(std::io::stdin().lock(), std::io::stdout());
    }

    pub fn serve<R: BufRead, W: Write + Send + 'static>(self, input: R, output: W) {
        let shared = Arc::new(Shared::new(Box::new(output)));
        let flusher = {
            let shared = shared.clone();
            thread::spawn(move || shared.flush_loop())
        };
        let mut workers = Vec::new();

        for line in input.lines() {
            let Ok(line) = line else { break };
            let Ok(message) = serde_json::from_str::<Value>(&line) else {
                continue;
            };
            match message.get("id") {
                // Answer to one of our own `shell.*` requests.
                Some(Value::String(id)) => shared.route_shell_answer(id, &message),
                Some(Value::Number(id)) => {
                    let Some(id) = id.as_u64() else { continue };
                    let method = message["method"].as_str().unwrap_or_default();
                    let Some(handler) = self.methods.get(method).cloned() else {
                        let error = Error::new("method_not_found", format!("unknown method {method}"));
                        shared.finish(id, Err(error));
                        continue;
                    };
                    let params = message.get("params").cloned().unwrap_or(Value::Null);
                    let ctx = Ctx {
                        shared: shared.clone(),
                        id,
                    };
                    workers.push(thread::spawn(move || {
                        let outcome = catch_unwind(AssertUnwindSafe(|| handler(params, &ctx)))
                            .unwrap_or_else(|_| Err(Error::new("internal", "handler panicked")));
                        ctx.shared.finish(id, outcome);
                    }));
                }
                _ if message["method"] == "cancel" => {
                    if let Some(id) = message["params"]["id"].as_u64() {
                        shared.cancelled.lock().unwrap().insert(id);
                    }
                }
                _ => {}
            }
            workers.retain(|worker| !worker.is_finished());
        }

        // stdin closed: the shell wants us gone, so running requests count as cancelled.
        shared.closed.store(true, Ordering::SeqCst);
        shared.shell_waiting.lock().unwrap().clear();
        for worker in workers {
            let _ = worker.join();
        }
        shared.stop_flusher();
        let _ = flusher.join();
    }
}

/// Per-request handle.
pub struct Ctx {
    shared: Arc<Shared>,
    id: u64,
}

impl Ctx {
    /// Streams an event to the UI, e.g. `json!({"type": "text_delta", "delta": "hi"})`.
    pub fn emit(&self, event: impl Serialize) {
        if let Ok(event) = serde_json::to_value(event) {
            self.shared.emit(self.id, event);
        }
    }

    /// True after the shell cancelled this request or closed stdin; return `Error::cancelled()` soon after.
    pub fn cancelled(&self) -> bool {
        self.shared.closed.load(Ordering::SeqCst) || self.shared.cancelled.lock().unwrap().contains(&self.id)
    }

    /// Calls a shell capability such as `shell.secret.get`; blocks until the shell answers.
    pub fn shell(&self, method: &str, params: Value) -> Result<Value, Error> {
        let id = format!("s{}", self.shared.shell_seq.fetch_add(1, Ordering::SeqCst) + 1);
        let (sender, receiver) = channel();
        self.shared
            .shell_waiting
            .lock()
            .unwrap()
            .insert(id.clone(), sender);
        self.shared
            .write(&json!({"id": id, "method": method, "params": params}));
        receiver
            .recv()
            .unwrap_or_else(|_| Err(Error::new("shell_closed", "shell closed the connection")))
    }
}

struct Pending {
    kind: String,
    text: String,
}

struct Shared {
    out: Mutex<Box<dyn Write + Send>>,
    cancelled: Mutex<HashSet<u64>>,
    closed: AtomicBool,
    shell_seq: AtomicU64,
    shell_waiting: Mutex<HashMap<String, Sender<Result<Value, Error>>>>,
    /// Buffered deltas per request. Held while writing, so a buffered delta can never be overtaken.
    deltas: Mutex<HashMap<u64, Pending>>,
    wake: Condvar,
    stopped: AtomicBool,
}

impl Shared {
    fn new(out: Box<dyn Write + Send>) -> Self {
        Shared {
            out: Mutex::new(out),
            cancelled: Mutex::default(),
            closed: AtomicBool::new(false),
            shell_seq: AtomicU64::new(0),
            shell_waiting: Mutex::default(),
            deltas: Mutex::default(),
            wake: Condvar::new(),
            stopped: AtomicBool::new(false),
        }
    }

    /// A closed pipe just means the shell is gone; there is nobody left to tell.
    fn write(&self, value: &Value) {
        let mut line = value.to_string();
        line.push('\n');
        let mut out = self.out.lock().unwrap();
        let _ = out.write_all(line.as_bytes()).and_then(|_| out.flush());
    }

    fn emit(&self, id: u64, event: Value) {
        let mut deltas = self.deltas.lock().unwrap();
        let Some((kind, text)) = delta_parts(&event) else {
            self.flush(&mut deltas, id);
            return self.write(&json!({"id": id, "event": event}));
        };
        match deltas.get_mut(&id) {
            Some(pending) if pending.kind == kind => pending.text.push_str(text),
            _ => {
                self.flush(&mut deltas, id);
                deltas.insert(
                    id,
                    Pending {
                        kind: kind.to_string(),
                        text: text.to_string(),
                    },
                );
                self.wake.notify_one();
            }
        }
    }

    fn finish(&self, id: u64, outcome: Result<Value, Error>) {
        let mut deltas = self.deltas.lock().unwrap();
        self.flush(&mut deltas, id);
        self.cancelled.lock().unwrap().remove(&id);
        self.write(&match outcome {
            Ok(result) => json!({"id": id, "result": result}),
            Err(error) => json!({"id": id, "error": {"code": error.code, "message": error.message}}),
        });
    }

    fn flush(&self, deltas: &mut MutexGuard<HashMap<u64, Pending>>, id: u64) {
        if let Some(pending) = deltas.remove(&id) {
            self.write(&json!({"id": id, "event": {"type": pending.kind, "delta": pending.text}}));
        }
    }

    fn flush_loop(&self) {
        loop {
            let mut deltas = self.deltas.lock().unwrap();
            while deltas.is_empty() && !self.stopped.load(Ordering::SeqCst) {
                deltas = self.wake.wait(deltas).unwrap();
            }
            drop(deltas);
            thread::sleep(COALESCE);
            let mut deltas = self.deltas.lock().unwrap();
            let ids: Vec<u64> = deltas.keys().copied().collect();
            for id in ids {
                self.flush(&mut deltas, id);
            }
            if self.stopped.load(Ordering::SeqCst) {
                return;
            }
        }
    }

    fn stop_flusher(&self) {
        let _guard = self.deltas.lock().unwrap();
        self.stopped.store(true, Ordering::SeqCst);
        self.wake.notify_all();
    }

    fn route_shell_answer(&self, id: &str, message: &Value) {
        let Some(sender) = self.shell_waiting.lock().unwrap().remove(id) else {
            return;
        };
        let answer = match message.get("error") {
            Some(error) => Err(Error::new(
                error["code"].as_str().unwrap_or("error"),
                error["message"].as_str().unwrap_or_default(),
            )),
            None => Ok(message.get("result").cloned().unwrap_or(Value::Null)),
        };
        let _ = sender.send(answer);
    }
}

/// `{"type": "x_delta", "delta": "..."}` and nothing else is eligible for merging.
fn delta_parts(event: &Value) -> Option<(&str, &str)> {
    let object = event.as_object()?;
    let kind = object.get("type")?.as_str()?;
    let text = object.get("delta")?.as_str()?;
    (object.len() == 2 && kind.ends_with("_delta")).then_some((kind, text))
}

#[cfg(test)]
mod tests;
