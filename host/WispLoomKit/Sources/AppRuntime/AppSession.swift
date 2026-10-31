import Foundation
import ShellCore

/// A running app: the backend process plus one link per open window. The backend is shared by all of the
/// app's windows and released with the last one. Page ↔ host messages are JSON; see docs/02-app-protocol.md.
@MainActor
public final class AppSession {
    public private(set) var bundle: AppBundle
    /// Menu-bar commands, by whichever window registered last (they are the same for every window).
    public private(set) var commands: [AppCommand] = []
    public var onCommandsChange: (@MainActor () -> Void)?
    public var onOpenSettings: (@MainActor () -> Void)?

    fileprivate let language: @MainActor () -> Language
    fileprivate let secrets: any SecretStore
    fileprivate let defaults: UserDefaults
    private let dataRoot: URL
    fileprivate let log: @Sendable (String) -> Void
    fileprivate var backend: BackendChannel?
    fileprivate var links: [Link] = []
    private var nextCallID = 1

    public init(
        bundle: AppBundle, dataRoot: URL, language: @escaping @MainActor () -> Language, secrets: any SecretStore,
        defaults: UserDefaults = .standard, log: @escaping @Sendable (String) -> Void
    ) {
        self.bundle = bundle
        self.dataRoot = dataRoot
        self.language = language
        self.secrets = secrets
        self.defaults = defaults
        self.log = log
    }

    public var isRunning: Bool { !links.isEmpty }
    public var windowCount: Int { links.count }

    /// One link per window. The first window starts the backend lazily (on its first call).
    public func connect(kind: WindowInstance.Kind = .main) -> any AppConnection {
        let link = Link(session: self, kind: kind)
        links.append(link)
        return link
    }

    public func update(_ bundle: AppBundle) { self.bundle = bundle }

    /// Dev hot reload of `ui.js`: every window reloads its page.
    public func reloadPages() { for link in links { link.reload?() } }

    public func restartBackend() { backend?.restartAfterRequests() }

    /// Tells a window's page that a menu command fired.
    public func fire(command: String) {
        for link in links.suffix(1) { link.push(["type": .string("command"), "id": .string(command)]) }
    }

    // MARK: -

    fileprivate func detach(_ link: Link) {
        links.removeAll { $0 === link }
        guard links.isEmpty else { return }
        backend?.shutdown()
        backend = nil
        commands = []
        onCommandsChange?()
    }

    fileprivate func backendChannel() -> BackendChannel? {
        if let backend { return backend }
        guard let spec = bundle.manifest.backend else { return nil }
        let shell = ShellCapabilities(appID: bundle.manifest.id, secrets: secrets)
        let channel = BackendChannel(
            config: BackendConfig(
                appID: bundle.manifest.id, command: spec.exec, directory: bundle.directory,
                dataDirectory: dataRoot.appendingPathComponent(bundle.manifest.id.rawValue),
                language: language().rawValue, idle: TimeInterval(spec.idle)),
            shell: { shell.handle($0, params: $1, from: .backend) }, log: log)
        backend = channel
        return channel
    }

    fileprivate func allocateCallID() -> Int {
        defer { nextCallID += 1 }
        return nextCallID
    }

    fileprivate func setCommands(_ list: [AppCommand]) {
        commands = list
        onCommandsChange?()
    }

    fileprivate final class Link: AppConnection {
        let session: AppSession
        var deliver: (@MainActor (String) -> Void)?
        var reload: (@MainActor () -> Void)?
        var onWindow: (@MainActor (WindowRequest) -> Void)?
        private var outbox: [String] = []
        private var flushing = false
        private var calls: Set<Int> = []
        private var closed = false

        let kind: WindowInstance.Kind

        init(session: AppSession, kind: WindowInstance.Kind) {
            self.session = session
            self.kind = kind
        }

        var appID: AppID { session.bundle.manifest.id }
        var directory: URL { session.bundle.directory }
        var script: String { session.bundle.manifest.ui }

        var bootstrap: String {
            let manifest = session.bundle.manifest
            let boot: [String: JSONValue] = [
                "appID": .string(manifest.id.rawValue), "lang": .string(session.language().rawValue),
                "title": .string(manifest.name.resolve(session.language())),
                "hasBackend": .bool(manifest.backend != nil),
                "window": .string(kind == .settings ? "settings" : "main"),
            ]
            return Self.encode(.object(boot))
        }

        func receive(_ json: String) {
            guard let message = try? JSONDecoder().decode([String: JSONValue].self, from: Data(json.utf8)) else {
                return
            }
            switch message["type"]?.stringValue {
            case "call": startCall(message)
            case "cancel":
                if let pageID = message["id"]?.numberValue, let id = pending[Int(pageID)] {
                    session.backend?.cancel(id: id)
                }
            case "title":
                onWindow?(.title(message["title"]?.stringValue ?? "", subtitle: message["subtitle"]?.stringValue))
            case "toolbar": applyToolbar(message)
            case "contextMenu": applyContextMenu(message)
            case "height": message["value"]?.numberValue.map { onWindow?(.contentHeight($0)) }
            case "setting": answerSetting(message)
            case "setSetting": storeSetting(message)
            case "commands": registerCommands(message)
            case "log": session.log("[\(appID.rawValue)] \(message["text"]?.stringValue ?? "")")
            case "openSettings": session.onOpenSettings?()
            default: break
            }
        }

        func close() {
            guard !closed else { return }
            closed = true
            for id in calls { session.backend?.cancel(id: id) }
            calls = []
            deliver = nil
            reload = nil
            onWindow = nil
            session.detach(self)
        }

        // MARK: Calls

        /// `{type:"call", id, method, params}`; the page's id is only used for the reply.
        private func startCall(_ message: [String: JSONValue]) {
            guard let pageID = message["id"]?.numberValue, let method = message["method"]?.stringValue else { return }
            let params = Self.encodeData(message["params"] ?? .null)
            let reply: @Sendable (CallReply) -> Void = { [weak self] reply in
                Task { @MainActor in self?.finish(pageID, reply) }
            }
            if method.hasPrefix("shell.") {
                let shell = ShellCapabilities(appID: appID, secrets: session.secrets)
                switch shell.handle(method, params: params, from: .ui) {
                case .success(let result): reply(.result(result))
                case .failure(let failure): reply(.failure(code: failure.code, message: failure.message))
                }
            } else if let backend = session.backendChannel() {
                let id = session.allocateCallID()
                pending[Int(pageID)] = id
                calls.insert(id)
                backend.call(id: id, method: method, params: params, reply: reply)
            } else {
                reply(.failure(code: "no_backend", message: "\(appID.rawValue) has no backend"))
            }
        }

        private var pending: [Int: Int] = [:]

        private func finish(_ pageID: Double, _ reply: CallReply) {
            var message: [String: JSONValue] = ["type": .string("reply"), "id": .number(pageID)]
            switch reply {
            case .event(let data): message["event"] = Self.decode(data)
            case .result(let data): message["result"] = Self.decode(data)
            case .failure(let code, let text):
                message["error"] = .object(["code": .string(code), "message": .string(text)])
            }
            if message["event"] == nil, let id = pending.removeValue(forKey: Int(pageID)) { calls.remove(id) }
            enqueue(Self.encode(.object(message)))
        }

        // MARK: Settings, commands

        private func answerSetting(_ message: [String: JSONValue]) {
            guard let id = message["id"]?.numberValue, let key = message["key"]?.stringValue else { return }
            let stored = session.defaults.string(forKey: settingKey(key))
            let value = stored.map { Self.decode(Data($0.utf8)) } ?? .null
            enqueue(Self.encode(.object(["type": .string("reply"), "id": .number(id), "result": value])))
        }

        private func storeSetting(_ message: [String: JSONValue]) {
            guard let key = message["key"]?.stringValue, let value = message["value"] else { return }
            session.defaults.set(Self.encode(value), forKey: settingKey(key))
            // Other windows of the same app (e.g. its settings window) show the new value live.
            for other in session.links where other !== self {
                other.push(["type": .string("settingChanged"), "key": .string(key), "value": value])
            }
        }

        private func settingKey(_ key: String) -> String { "wisploom.app.\(appID.rawValue).\(key)" }

        private func registerCommands(_ message: [String: JSONValue]) {
            guard let list = message["commands"], let data = try? JSONEncoder().encode(list),
                let commands = try? JSONDecoder().decode([AppCommand].self, from: data)
            else { return }
            session.setCommands(commands)
        }

        private func applyContextMenu(_ message: [String: JSONValue]) {
            guard let value = message["items"], let data = try? JSONEncoder().encode(value),
                let items = try? JSONDecoder().decode([ToolbarMenuItem].self, from: data), !items.isEmpty
            else { return }
            onWindow?(.contextMenu(items))
        }

        private func applyToolbar(_ message: [String: JSONValue]) {
            guard let value = message["spec"], let data = try? JSONEncoder().encode(value),
                let spec = try? JSONDecoder().decode(ToolbarSpec.self, from: data)
            else { return }
            onWindow?(.toolbar(spec))
        }

        // MARK: Delivery

        func push(_ message: [String: JSONValue]) { enqueue(Self.encode(.object(message))) }

        /// Replies that arrive in the same turn go out as one array: one WebKit call, not many.
        private func enqueue(_ json: String) {
            outbox.append(json)
            guard !flushing else { return }
            flushing = true
            Task { @MainActor [weak self] in
                guard let self else { return }
                flushing = false
                let batch = "[" + outbox.joined(separator: ",") + "]"
                outbox = []
                deliver?(batch)
            }
        }

        private static func encodeData(_ value: JSONValue) -> Data {
            (try? JSONEncoder().encode(value)) ?? Data("null".utf8)
        }
        private static func encode(_ value: JSONValue) -> String { String(decoding: encodeData(value), as: UTF8.self) }
        private static func decode(_ data: Data) -> JSONValue {
            (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .null
        }
    }
}
