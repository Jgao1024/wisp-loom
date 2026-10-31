import Foundation
import ShellCore
import Testing

@testable import AppRuntime

@MainActor
struct AppSessionTests {
    private func session(_ box: Sandbox, secrets: MemorySecrets = MemorySecrets(), backend: Bool = true) throws
        -> AppSession
    {
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

    /// Collects what the host sends to the page.
    @MainActor private final class Page {
        var messages: [[String: JSONValue]] = []
        let connection: any AppConnection

        init(_ session: AppSession, kind: WindowInstance.Kind = .main) {
            connection = session.connect(kind: kind)
            connection.deliver = { [weak self] batch in
                let list = (try? JSONDecoder().decode([[String: JSONValue]].self, from: Data(batch.utf8))) ?? []
                self?.messages.append(contentsOf: list)
            }
        }

        func send(_ json: String) { connection.receive(json) }

        func reply(_ id: Int) -> [[String: JSONValue]] { messages.filter { $0["id"]?.numberValue == Double(id) } }

        func waitForReply(_ id: Int, terminal: Bool = true) async -> Bool {
            let deadline = Date().addingTimeInterval(5)
            func done() -> Bool { reply(id).contains { !terminal || $0["event"] == nil } }
            while !done() && Date() < deadline { try? await Task.sleep(for: .milliseconds(5)) }
            return done()
        }
    }

    @Test func bootstrapDescribesTheApp() throws {
        let box = try Sandbox()
        defer { box.remove() }
        let link = try session(box).connect(kind: .settings)
        let boot = try JSONDecoder().decode([String: JSONValue].self, from: Data(link.bootstrap.utf8))
        #expect(boot["appID"]?.stringValue == "test.app")
        #expect(boot["window"]?.stringValue == "settings")
        #expect(boot["lang"]?.stringValue == "en")
        #expect(boot["hasBackend"]?.boolValue == true)
        link.close()
    }

    @Test func callReachesBackendAndStreamsEventsThenResult() async throws {
        let box = try Sandbox()
        defer { box.remove() }
        let session = try session(box)
        let page = Page(session)
        defer { page.connection.close() }
        page.send(#"{"type":"call","id":7,"method":"echo","params":{"n":2}}"#)
        #expect(await page.waitForReply(7))
        let kinds = page.reply(7).map { $0["event"] != nil ? "event" : ($0["result"] != nil ? "result" : "other") }
        #expect(kinds == ["event", "event", "result"])
        #expect(page.reply(7).last?["result"] == .object(["n": .number(2)]))
    }

    @Test func eventsFromOneTurnArriveAsOneBatch() async throws {
        let box = try Sandbox()
        defer { box.remove() }
        let session = try session(box, backend: false)
        let link = session.connect()
        defer { link.close() }
        let batches = Inbox<String>()
        link.deliver = { batches.add($0) }
        link.receive(#"{"type":"call","id":1,"method":"a","params":null}"#)
        link.receive(#"{"type":"call","id":2,"method":"b","params":null}"#)
        let first = await batches.wait(count: 1)
        try await Task.sleep(for: .milliseconds(50))
        #expect(first.count == 1 && batches.all.count == 1)
        #expect(first[0].hasPrefix("[") && first[0].contains(#""id":1"#) && first[0].contains(#""id":2"#))
    }

    @Test func callWithoutBackendFails() async throws {
        let box = try Sandbox()
        defer { box.remove() }
        let page = Page(try session(box, backend: false))
        defer { page.connection.close() }
        page.send(#"{"type":"call","id":1,"method":"echo","params":{}}"#)
        #expect(await page.waitForReply(1))
        #expect(page.reply(1).last?["error"]?.objectValue?["code"]?.stringValue == "no_backend")
    }

    @Test func cancelUsesThePagesId() async throws {
        let box = try Sandbox()
        defer { box.remove() }
        let session = try session(box)
        let page = Page(session)
        defer { page.connection.close() }
        page.send(#"{"type":"call","id":41,"method":"slow","params":{}}"#)
        try await Task.sleep(for: .milliseconds(200))
        page.send(#"{"type":"cancel","id":41}"#)
        #expect(await page.waitForReply(41))
        #expect(page.reply(41).last?["error"]?.objectValue?["code"]?.stringValue == "cancelled")
    }

    @Test func pageCanSetButNeverReadSecrets() async throws {
        let box = try Sandbox()
        defer { box.remove() }
        let secrets = MemorySecrets()
        let page = Page(try session(box, secrets: secrets, backend: false))
        defer { page.connection.close() }
        page.send(#"{"type":"call","id":1,"method":"shell.secret.set","params":{"key":"token","value":"hunter2"}}"#)
        page.send(#"{"type":"call","id":2,"method":"shell.secret.get","params":{"key":"token"}}"#)
        #expect(await page.waitForReply(1))
        #expect(await page.waitForReply(2))
        #expect(secrets.get(app: "test.app", key: "token") == "hunter2")
        #expect(page.reply(2).last?["error"]?.objectValue?["code"]?.stringValue == "forbidden")
        #expect(!page.messages.contains { String(describing: $0).contains("hunter2") })
    }

    @Test func backendCanReadItsOwnSecretOnly() async throws {
        let box = try Sandbox()
        defer { box.remove() }
        let secrets = MemorySecrets()
        try secrets.set(app: "test.app", key: "token", value: "hunter2")
        try secrets.set(app: "other.app", key: "token", value: "not-mine")
        let page = Page(try session(box, secrets: secrets))
        defer { page.connection.close() }
        page.send(#"{"type":"call","id":1,"method":"secret","params":{}}"#)
        #expect(await page.waitForReply(1))
        let text = String(describing: page.reply(1))
        #expect(text.contains("hunter2") && !text.contains("not-mine"))
    }

    @Test func settingsRoundTripAndReachOtherWindows() async throws {
        let box = try Sandbox()
        defer { box.remove() }
        let session = try session(box, backend: false)
        let main = Page(session)
        let settings = Page(session, kind: .settings)
        defer {
            main.connection.close()
            settings.connection.close()
        }
        settings.send(#"{"type":"setSetting","key":"name","value":"Hello"}"#)
        main.send(#"{"type":"setting","id":5,"key":"name"}"#)
        main.send(#"{"type":"setting","id":6,"key":"missing"}"#)
        #expect(await main.waitForReply(5))
        #expect(await main.waitForReply(6))
        #expect(main.reply(5).last?["result"] == .string("Hello"))
        #expect(main.reply(6).last?["result"] == .null)
        // The other window hears about the change instead of polling.
        #expect(
            main.messages.contains { $0["type"]?.stringValue == "settingChanged" && $0["value"] == .string("Hello") })
        #expect(!settings.messages.contains { $0["type"]?.stringValue == "settingChanged" })
    }

    @Test func commandsAreStoredAndFired() async throws {
        let box = try Sandbox()
        defer { box.remove() }
        let session = try session(box, backend: false)
        let page = Page(session)
        defer { page.connection.close() }
        var changes = 0
        session.onCommandsChange = { changes += 1 }
        page.send(#"{"type":"commands","commands":[{"id":"new","menu":"file","title":"New","shortcut":"cmd+n"}]}"#)
        #expect(session.commands.map(\.title) == ["New"])
        #expect(session.commands[0].shortcut == Shortcut("cmd+n"))
        session.fire(command: "new")
        for _ in 0..<200 where !page.messages.contains(where: { $0["type"]?.stringValue == "command" }) {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(page.messages.last?["id"] == .string("new"))
        #expect(changes == 1)
    }

    @Test func lastWindowReleasesTheBackendAndCommands() async throws {
        let box = try Sandbox()
        defer { box.remove() }
        let session = try session(box)
        let first = Page(session)
        let second = Page(session, kind: .settings)
        first.send(#"{"type":"call","id":1,"method":"echo","params":1}"#)
        #expect(await first.waitForReply(1))
        first.send(#"{"type":"commands","commands":[{"id":"x","menu":"file","title":"X"}]}"#)
        #expect(session.windowCount == 2)
        first.connection.close()
        #expect(session.isRunning && session.commands.count == 1)
        second.connection.close()
        #expect(!session.isRunning && session.commands.isEmpty)
    }

    @Test func closingCancelsInFlightCalls() async throws {
        let box = try Sandbox()
        defer { box.remove() }
        let session = try session(box)
        let page = Page(session)
        page.send(#"{"type":"call","id":1,"method":"slow","params":{}}"#)
        try await Task.sleep(for: .milliseconds(200))
        page.connection.close()
        page.connection.close()  // idempotent
        #expect(!session.isRunning)
    }

    @Test func windowRequestsAreForwarded() throws {
        let box = try Sandbox()
        defer { box.remove() }
        let link = try session(box, backend: false).connect()
        defer { link.close() }
        var seen: [WindowRequest] = []
        link.onWindow = { seen.append($0) }
        link.receive(#"{"type":"title","title":"Hi","subtitle":"There"}"#)
        link.receive(#"{"type":"height","value":300}"#)
        link.receive(
            #"{"type":"toolbar","spec":{"leading":[{"id":"new","symbol":"plus","help":"New"}],"trailing":[{"id":"search","search":true,"placeholder":"Search"}]}}"#
        )
        link.receive(
            #"{"type":"contextMenu","items":[{"id":"rename","title":"Rename"},{"id":"delete","title":"Delete","destructive":true,"disabled":true}]}"#
        )
        let spec = ToolbarSpec(
            leading: [ToolbarItem(id: "new", symbol: "plus", help: "New")],
            trailing: [ToolbarItem(id: "search", search: true, placeholder: "Search")])
        let menu = [
            ToolbarMenuItem(id: "rename", title: "Rename"),
            ToolbarMenuItem(id: "delete", title: "Delete", destructive: true, isEnabled: false),
        ]
        #expect(
            seen == [.title("Hi", subtitle: "There"), .contentHeight(300), .toolbar(spec), .contextMenu(menu)])
    }
}
