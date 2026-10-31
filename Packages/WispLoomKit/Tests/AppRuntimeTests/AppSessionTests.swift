import Foundation
import ShellCore
import Testing

@testable import AppRuntime

@MainActor
struct AppSessionTests {
    private func session(_ box: Sandbox, ui: String, secrets: MemorySecrets = MemorySecrets(), backend: Bool = true)
        throws
        -> AppSession
    {
        try box.write("ui.js", ui)
        try box.write("backend.py", fakeBackend)
        let json = """
            {"id":"test.app","name":"T","symbol":"star","ui":"ui.js"
            \(backend ? #","backend":{"exec":["python3","backend.py"],"idle":0}"# : "")}
            """
        let manifest = try Manifest.decode(Data(json.utf8))
        return AppSession(
            bundle: AppBundle(directory: box.directory, manifest: manifest), dataRoot: box.data, language: { .en },
            secrets: secrets, defaults: UserDefaults(suiteName: "wisploom.tests." + UUID().uuidString)!, log: { _ in })
    }

    private func settle(_ session: AppSession, until condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { try? await Task.sleep(for: .milliseconds(5)) }
        return condition()
    }

    private let rootScript = """
        __wisp.commit(JSON.stringify({rev: (__wisp.rev || 0) + 1, ops: [{op: "replace", node: {id: "r", type: "Text", props: {text: "hi"}, children: []}}]}));
        """

    @Test func scriptCommitReachesTheTree() async throws {
        let box = try Sandbox()
        defer { box.remove() }
        let session = try session(box, ui: rootScript, backend: false)
        session.retain()
        defer { session.release() }
        #expect(await settle(session) { session.tree.root != nil })
        #expect(session.tree.root?.string("text") == "hi")
    }

    @Test func callRoundTripsThroughBackendAndSettingsPersist() async throws {
        let box = try Sandbox()
        defer { box.remove() }
        let ui = """
            __wisp.call("echo", JSON.stringify({n: 2}), function (e) { console.log("event " + e); },
              function (result, error) {
                __wisp.setSetting("result", result);
                __wisp.commit(JSON.stringify({rev: 1, ops: [{op: "replace", node: {id: "r", type: "Text", props: {text: result}, children: []}}]}));
              });
            """
        let session = try session(box, ui: ui)
        session.retain()
        defer { session.release() }
        #expect(await settle(session) { session.tree.root != nil })
        #expect(session.tree.root?.string("text") == #"{"n":2}"#)
    }

    @Test func timersFireAndCanBeCleared() async throws {
        let box = try Sandbox()
        defer { box.remove() }
        let ui = """
            var gone = setTimeout(function () { __wisp.commit(JSON.stringify({rev: 1, ops: [{op: "replace", node: {id: "bad", type: "Text", props: {}, children: []}}]})); }, 20);
            clearTimeout(gone);
            setTimeout(function () { __wisp.commit(JSON.stringify({rev: 2, ops: [{op: "replace", node: {id: "ok", type: "Text", props: {}, children: []}}]})); }, 40);
            """
        let session = try session(box, ui: ui, backend: false)
        session.retain()
        defer { session.release() }
        #expect(await settle(session) { session.tree.root != nil })
        #expect(session.tree.root?.id == "ok")
    }

    @Test func uiCanSetButNeverReadSecrets() async throws {
        let box = try Sandbox()
        defer { box.remove() }
        let secrets = MemorySecrets()
        let ui = """
            function show(label) { return function (result, error) {
              __wisp.commit(JSON.stringify({rev: __wisp.next = (__wisp.next || 0) + 1, ops: [{op: "replace", node: {id: "r", type: "Text", props: {text: label + ":" + (error ? JSON.parse(error).code : result)}, children: []}}]}));
            }; }
            __wisp.call("shell.secret.set", JSON.stringify({key: "token", value: "hunter2"}), function () {}, function () {
              __wisp.call("shell.secret.get", JSON.stringify({key: "token"}), function () {}, show("get"));
            });
            """
        let session = try session(box, ui: ui, secrets: secrets, backend: false)
        session.retain()
        defer { session.release() }
        #expect(await settle(session) { session.tree.root?.string("text") == "get:forbidden" })
        #expect(secrets.get(app: "test.app", key: "token") == "hunter2")
    }

    @Test func backendCanReadItsOwnSecret() async throws {
        let box = try Sandbox()
        defer { box.remove() }
        let secrets = MemorySecrets()
        try secrets.set(app: "test.app", key: "token", value: "hunter2")
        try secrets.set(app: "other.app", key: "token", value: "not-mine")
        let ui = """
            __wisp.call("secret", "{}", function () {}, function (result) {
              __wisp.commit(JSON.stringify({rev: 1, ops: [{op: "replace", node: {id: "r", type: "Text", props: {text: result}, children: []}}]}));
            });
            """
        let session = try session(box, ui: ui, secrets: secrets)
        session.retain()
        defer { session.release() }
        #expect(await settle(session) { session.tree.root != nil })
        #expect(session.tree.root?.string("text")?.contains("hunter2") == true)
        #expect(session.tree.root?.string("text")?.contains("not-mine") == false)
    }

    @Test func releaseFreesContextAndNodeTable() async throws {
        let box = try Sandbox()
        defer { box.remove() }
        let session = try session(box, ui: rootScript, backend: false)
        session.retain()
        session.retain()
        #expect(await settle(session) { session.tree.root != nil })
        session.release()
        #expect(session.isRunning)
        session.release()
        #expect(!session.isRunning)
        #expect(session.tree.root == nil)
    }

    @Test func reloadKeepsRevisionsIncreasing() async throws {
        let box = try Sandbox()
        defer { box.remove() }
        let session = try session(box, ui: rootScript, backend: false)
        session.retain()
        defer { session.release() }
        #expect(await settle(session) { session.tree.rev == 1 })
        session.reloadScript()
        #expect(await settle(session) { session.tree.rev == 2 })
    }

    @Test func rejectedPatchAsksForResync() async throws {
        let box = try Sandbox()
        defer { box.remove() }
        let ui = """
            __wisp.lifecycle = function (kind) {
              if (kind === "resync") __wisp.commit(JSON.stringify({rev: 3, ops: [{op: "replace", node: {id: "r", type: "Text", props: {text: "fixed"}, children: []}}]}));
            };
            __wisp.commit(JSON.stringify({rev: 1, ops: [{op: "replace", node: {id: "r", type: "Text", props: {}, children: []}}]}));
            __wisp.commit(JSON.stringify({rev: 2, ops: [{op: "remove", id: "nope"}]}));
            """
        let session = try session(box, ui: ui, backend: false)
        session.retain()
        defer { session.release() }
        #expect(await settle(session) { session.tree.root?.string("text") == "fixed" })
    }
}
