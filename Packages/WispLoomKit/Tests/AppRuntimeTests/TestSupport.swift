import Foundation
import ShellCore

@testable import AppRuntime

/// Thread-safe collector for results arriving on arbitrary queues.
final class Inbox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [T] = []

    func add(_ item: T) { lock.withLock { items.append(item) } }
    var all: [T] { lock.withLock { items } }

    func wait(count: Int, timeout: TimeInterval = 5) async -> [T] {
        let deadline = Date().addingTimeInterval(timeout)
        while all.count < count && Date() < deadline { try? await Task.sleep(for: .milliseconds(5)) }
        return all
    }
}

func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline { try? await Task.sleep(for: .milliseconds(5)) }
    return condition()
}

final class MemorySecrets: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func get(app: AppID, key: String) -> String? { lock.withLock { values[app.rawValue + "/" + key] } }
    func set(app: AppID, key: String, value: String) throws {
        lock.withLock { values[app.rawValue + "/" + key] = value }
    }
    func delete(app: AppID, key: String) throws {
        _ = lock.withLock { values.removeValue(forKey: app.rawValue + "/" + key) }
    }
}

/// A scratch directory holding a fake backend script (Python, standard library only).
struct Sandbox {
    let directory: URL
    let data: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("wisp-test-" + UUID().uuidString)
        data = directory.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }

    func write(_ name: String, _ text: String) throws {
        try text.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func config(script: String, idle: TimeInterval = 0, grace: TimeInterval = 0.3) throws -> BackendConfig {
        try write("backend.py", script)
        return BackendConfig(
            appID: "test.app", command: ["python3", "backend.py"], directory: directory, dataDirectory: data,
            language: "en", idle: idle, termGrace: grace)
    }
}

/// Echo backend: `echo` streams two events then returns params; `slow` waits for cancel; `crash` exits;
/// `env` returns the WISP_* variables; `secret` asks the shell for a secret.
let fakeBackend = #"""
    import json, os, sys, threading, time

    out_lock = threading.Lock()
    cancelled = set()
    answers = {}

    def send(obj):
        with out_lock:
            sys.stdout.write(json.dumps(obj) + "\n")
            sys.stdout.flush()

    def handle(msg):
        rid, method, params = msg["id"], msg["method"], msg.get("params")
        if method == "echo":
            send({"id": rid, "event": {"type": "text_delta", "delta": "a"}})
            send({"id": rid, "event": {"type": "text_delta", "delta": "b"}})
            send({"id": rid, "result": params})
        elif method == "slow":
            for _ in range(500):
                if rid in cancelled:
                    send({"id": rid, "error": {"code": "cancelled", "message": "cancelled"}})
                    return
                time.sleep(0.01)
            send({"id": rid, "result": "late"})
        elif method == "wait":
            time.sleep(params["seconds"])
            send({"id": rid, "result": "done"})
        elif method == "crash":
            os._exit(3)
        elif method == "env":
            send({"id": rid, "result": {k: os.environ.get(k) for k in ("WISP_APP_ID", "WISP_DATA_DIR", "WISP_LANG")}})
        elif method == "secret":
            send({"id": "s1", "method": "shell.secret.get", "params": {"key": "token"}})
            for _ in range(300):
                if "s1" in answers:
                    break
                time.sleep(0.01)
            send({"id": rid, "result": answers.get("s1")})

    for line in sys.stdin:
        msg = json.loads(line)
        if msg.get("method") == "cancel":
            cancelled.add(msg["params"]["id"])
        elif "id" in msg and "method" in msg:
            threading.Thread(target=handle, args=(msg,)).start()
        elif msg.get("id") == "s1":
            answers["s1"] = msg
    """#
