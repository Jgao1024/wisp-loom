import io
import json
import os
import subprocess
import sys
import threading
import time
import unittest

from wisp_backend import Backend, Error


class Session:
    """Runs a Backend on pipes so the test talks to it like the shell does."""

    def __init__(self, backend):
        in_r, in_w = os.pipe()
        out_r, out_w = os.pipe()
        self.stdin = os.fdopen(in_w, "w")
        self.stdout = os.fdopen(out_r, "r")
        self.lines = []
        self.out = os.fdopen(out_w, "w")
        self.server = threading.Thread(target=backend.serve, args=(os.fdopen(in_r, "r"), self.out))
        self.server.start()

    def send(self, value):
        self.stdin.write(json.dumps(value) + "\n")
        self.stdin.flush()

    def read_until(self, done):
        while not done(self.lines):
            line = self.stdout.readline()
            if not line:
                break
            self.lines.append(json.loads(line))
        return self.lines

    def finish(self):
        self.stdin.close()
        self.server.join(5)
        self.out.close()  # EOF for the reader, as when a real backend exits
        return self.read_until(lambda _: False)


def finished(lines, ident):
    return any(m.get("id") == ident and ("result" in m or "error" in m) for m in lines)


class BackendTests(unittest.TestCase):
    def test_result_and_event(self):
        backend = Backend()

        @backend.method("echo")
        def echo(params, ctx):
            ctx.emit({"type": "progress", "pct": 50})
            return params

        s = Session(backend)
        s.send({"id": 1, "method": "echo", "params": {"x": 1}})
        lines = s.read_until(lambda l: finished(l, 1))
        self.assertEqual(lines[0], {"id": 1, "event": {"type": "progress", "pct": 50}})
        self.assertEqual(lines[1], {"id": 1, "result": {"x": 1}})
        s.finish()

    def test_errors(self):
        backend = Backend()

        @backend.method("fail")
        def fail(params, ctx):
            raise Error("http_401", "bad key")

        @backend.method("boom")
        def boom(params, ctx):
            raise RuntimeError("oops")

        s = Session(backend)
        for ident, method in ((1, "nope"), (2, "fail"), (3, "boom")):
            s.send({"id": ident, "method": method})
        lines = s.read_until(lambda l: all(finished(l, i) for i in (1, 2, 3)))
        error = {m["id"]: m["error"] for m in lines}
        self.assertEqual(error[1]["code"], "method_not_found")
        self.assertEqual(error[2], {"code": "http_401", "message": "bad key"})
        self.assertEqual(error[3]["code"], "internal")
        s.finish()

    def test_concurrent_requests_and_cancel(self):
        backend = Backend()

        @backend.method("slow")
        def slow(params, ctx):
            while not ctx.cancelled():
                time.sleep(0.005)
            raise Error("cancelled")

        @backend.method("fast")
        def fast(params, ctx):
            return "fast"

        s = Session(backend)
        s.send({"id": 1, "method": "slow"})
        s.send({"id": 2, "method": "fast"})
        lines = s.read_until(lambda l: finished(l, 2))
        self.assertFalse(finished(lines, 1))
        s.send({"method": "cancel", "params": {"id": 1}})
        lines = s.read_until(lambda l: finished(l, 1))
        self.assertEqual([m for m in lines if m["id"] == 1][-1]["error"]["code"], "cancelled")
        s.finish()

    def test_closing_stdin_cancels_running_requests(self):
        backend = Backend()

        @backend.method("slow")
        def slow(params, ctx):
            while not ctx.cancelled():
                time.sleep(0.005)
            raise Error("cancelled")

        s = Session(backend)
        s.send({"id": 1, "method": "slow"})
        time.sleep(0.05)
        self.assertEqual(s.finish()[-1]["error"]["code"], "cancelled")

    def test_deltas_coalesce_and_stay_ordered(self):
        backend = Backend()

        @backend.method("stream")
        def stream(params, ctx):
            for piece in "abcd":
                ctx.emit({"type": "text_delta", "delta": piece})
            ctx.emit({"type": "tool_start", "name": "x"})
            ctx.emit({"type": "text_delta", "delta": "e"})
            return "done"

        s = Session(backend)
        s.send({"id": 1, "method": "stream"})
        lines = s.read_until(lambda l: finished(l, 1))
        self.assertEqual(
            [m["event"] for m in lines if "event" in m],
            [
                {"type": "text_delta", "delta": "abcd"},
                {"type": "tool_start", "name": "x"},
                {"type": "text_delta", "delta": "e"},
            ],
        )
        self.assertEqual(lines[-1]["result"], "done")
        s.finish()

    def test_deltas_flush_on_a_timer_while_running(self):
        backend = Backend()

        @backend.method("hold")
        def hold(params, ctx):
            ctx.emit({"type": "text_delta", "delta": "hi"})
            while not ctx.cancelled():
                time.sleep(0.005)

        s = Session(backend)
        s.send({"id": 1, "method": "hold"})
        lines = s.read_until(lambda l: any(m.get("event", {}).get("delta") == "hi" for m in l))
        self.assertEqual(lines[0]["event"]["delta"], "hi")
        s.finish()

    def test_shell_round_trip(self):
        backend = Backend()

        @backend.method("needs_key")
        def needs_key(params, ctx):
            return ctx.shell("shell.secret.get", {"key": "token"})

        s = Session(backend)
        s.send({"id": 1, "method": "needs_key"})
        lines = s.read_until(lambda l: any(m.get("id") == "s1" for m in l))
        self.assertEqual(lines[0], {"id": "s1", "method": "shell.secret.get", "params": {"key": "token"}})
        s.send({"id": "s1", "result": "hunter2"})
        lines = s.read_until(lambda l: finished(l, 1))
        self.assertEqual(lines[-1]["result"], "hunter2")
        s.finish()

    def test_shell_error(self):
        backend = Backend()

        @backend.method("needs_key")
        def needs_key(params, ctx):
            return ctx.shell("shell.secret.get", {"key": "token"})

        s = Session(backend)
        s.send({"id": 1, "method": "needs_key"})
        s.read_until(lambda l: any(m.get("id") == "s1" for m in l))
        s.send({"id": "s1", "error": {"code": "forbidden", "message": "no"}})
        lines = s.read_until(lambda l: finished(l, 1))
        self.assertEqual(lines[-1]["error"]["code"], "forbidden")
        s.finish()

    def test_real_process_over_stdio(self):
        script = (
            "from wisp_backend import Backend\n"
            "b = Backend()\n"
            "@b.method('echo')\n"
            "def echo(p, ctx):\n"
            "    ctx.emit({'type': 'text_delta', 'delta': p['t']})\n"
            "    return p\n"
            "b.run()\n"
        )
        here = os.path.dirname(os.path.abspath(__file__))
        proc = subprocess.run(
            [sys.executable, "-c", script],
            input=json.dumps({"id": 1, "method": "echo", "params": {"t": "hi"}}) + "\n",
            capture_output=True,
            text=True,
            cwd=here,
            timeout=10,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        lines = [json.loads(l) for l in proc.stdout.splitlines()]
        self.assertEqual(lines[-1], {"id": 1, "result": {"t": "hi"}})


if __name__ == "__main__":
    unittest.main()
