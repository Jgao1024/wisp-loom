"""Backend SDK: a stdio JSON Lines loop with one thread per request (standard library only).
Protocol: docs/02-app-protocol.md section 3. Same interface as the Rust crate wisp-backend."""

import json
import sys
import threading
import traceback

COALESCE = 0.016  # same-kind *_delta events are merged for this long


class Error(Exception):
    def __init__(self, code, message=""):
        super().__init__(message or code)
        self.code = code
        self.message = message or code


class Ctx:
    """Per-request handle passed to every method."""

    def __init__(self, backend, request_id):
        self._backend = backend
        self._id = request_id

    def emit(self, event):
        """Streams an event to the UI, e.g. {"type": "text_delta", "delta": "hi"}."""
        self._backend._emit(self._id, event)

    def cancelled(self):
        """True after the shell cancelled this request or closed stdin; raise Error("cancelled") soon after."""
        return self._backend._closed.is_set() or self._id in self._backend._cancelled

    def shell(self, method, params=None):
        """Calls a shell capability such as shell.secret.get; blocks until the shell answers."""
        return self._backend._shell(method, params or {})


class Backend:
    def __init__(self):
        self._methods = {}
        self._out = None
        self._write_lock = threading.Lock()
        self._cancelled = set()
        self._closed = threading.Event()
        self._shell_seq = 0
        self._shell_waiting = {}
        # Buffered deltas per request id; the lock is held while writing so nothing overtakes a buffered delta.
        self._deltas = {}
        self._deltas_lock = threading.Condition()
        self._stopped = False

    def method(self, name):
        """Decorator: @backend.method("echo") def echo(params, ctx): ..."""

        def register(fn):
            self._methods[name] = fn
            return fn

        return register

    def run(self):
        self.serve(sys.stdin, sys.stdout)

    def serve(self, source, out):
        """Serves until `source` reaches EOF, then waits for running requests."""
        self._out = out
        flusher = threading.Thread(target=self._flush_loop)
        flusher.start()
        workers = []
        for line in source:
            try:
                message = json.loads(line)
            except ValueError:
                continue
            ident = message.get("id")
            if isinstance(ident, str):
                self._shell_answer(ident, message)
            elif isinstance(ident, int):
                handler = self._methods.get(message.get("method"))
                if handler is None:
                    self._finish(ident, error=Error("method_not_found", "unknown method %s" % message.get("method")))
                    continue
                worker = threading.Thread(target=self._run_request, args=(handler, ident, message.get("params")))
                worker.start()
                workers.append(worker)
            elif message.get("method") == "cancel":
                self._cancelled.add(message["params"]["id"])
            workers = [w for w in workers if w.is_alive()]
        # stdin closed: the shell wants us gone, so running requests count as cancelled.
        self._closed.set()
        for waiting in list(self._shell_waiting.values()):
            waiting["answer"] = {"error": {"code": "shell_closed", "message": "shell closed the connection"}}
            waiting["event"].set()
        for worker in workers:
            worker.join()
        with self._deltas_lock:
            self._stopped = True
            self._deltas_lock.notify_all()
        flusher.join()

    def _run_request(self, handler, request_id, params):
        try:
            self._finish(request_id, result=handler(params, Ctx(self, request_id)))
        except Error as error:
            self._finish(request_id, error=error)
        except Exception as error:  # a bug in one method must not take the loop down
            traceback.print_exc(file=sys.stderr)
            self._finish(request_id, error=Error("internal", str(error)))

    def _write(self, value):
        # A closed pipe means the shell is gone; there is nobody left to tell.
        with self._write_lock:
            try:
                self._out.write(json.dumps(value, ensure_ascii=False) + "\n")
                self._out.flush()
            except (BrokenPipeError, ValueError):
                pass

    def _emit(self, request_id, event):
        with self._deltas_lock:
            parts = _delta_parts(event)
            if parts is None:
                self._flush(request_id)
                return self._write({"id": request_id, "event": event})
            kind, text = parts
            pending = self._deltas.get(request_id)
            if pending is not None and pending[0] == kind:
                pending[1].append(text)
                return
            self._flush(request_id)
            self._deltas[request_id] = (kind, [text])
            self._deltas_lock.notify()

    def _finish(self, request_id, result=None, error=None):
        with self._deltas_lock:
            self._flush(request_id)
            self._cancelled.discard(request_id)
            if error is None:
                self._write({"id": request_id, "result": result})
            else:
                self._write({"id": request_id, "error": {"code": error.code, "message": error.message}})

    def _flush(self, request_id):
        pending = self._deltas.pop(request_id, None)
        if pending is not None:
            self._write({"id": request_id, "event": {"type": pending[0], "delta": "".join(pending[1])}})

    def _flush_loop(self):
        while True:
            with self._deltas_lock:
                while not self._deltas and not self._stopped:
                    self._deltas_lock.wait()
            if self._stopped and not self._deltas:
                return
            self._closed.wait(COALESCE)
            with self._deltas_lock:
                for request_id in list(self._deltas):
                    self._flush(request_id)
                if self._stopped:
                    return

    def _shell(self, method, params):
        if self._closed.is_set():
            raise Error("shell_closed", "shell closed the connection")
        with self._write_lock:
            self._shell_seq += 1
            ident = "s%d" % self._shell_seq
        waiting = {"event": threading.Event(), "answer": None}
        self._shell_waiting[ident] = waiting
        self._write({"id": ident, "method": method, "params": params})
        waiting["event"].wait()
        self._shell_waiting.pop(ident, None)
        answer = waiting["answer"]
        if "error" in answer:
            raise Error(answer["error"].get("code", "error"), answer["error"].get("message", ""))
        return answer.get("result")

    def _shell_answer(self, ident, message):
        waiting = self._shell_waiting.get(ident)
        if waiting is not None:
            waiting["answer"] = message
            waiting["event"].set()


def _delta_parts(event):
    """{"type": "x_delta", "delta": "..."} and nothing else is eligible for merging."""
    if isinstance(event, dict) and len(event) == 2:
        kind, text = event.get("type"), event.get("delta")
        if isinstance(kind, str) and kind.endswith("_delta") and isinstance(text, str):
            return kind, text
    return None
