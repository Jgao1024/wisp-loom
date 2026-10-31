import Foundation
import ShellCore

/// A running app: its UI tree, JS context and backend. Lives as long as the app has windows;
/// the JS context and backend are created on the first window and released with the last one.
@MainActor
public final class AppSession {
    public private(set) var bundle: AppBundle
    public let tree = UITree()

    private let language: @MainActor () -> Language
    private let secrets: any SecretStore
    private let defaults: UserDefaults
    private let dataRoot: URL
    private let log: @Sendable (String) -> Void
    private var host: JSHost?
    private var backend: BackendChannel?
    private var windows = 0

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

    public var isRunning: Bool { host != nil }

    /// Called per window; the first one starts the app.
    public func retain() {
        windows += 1
        guard host == nil else { return }
        guard let script = try? String(contentsOf: bundle.scriptURL, encoding: .utf8) else {
            return log("[\(bundle.manifest.id.rawValue)] cannot read \(bundle.manifest.ui)")
        }
        startBackend()
        startHost(script, startRev: tree.rev, firstCallID: 1)
    }

    /// The last window going away drops the JS context, the backend and the node table.
    public func release() {
        windows = max(0, windows - 1)
        guard windows == 0 else { return }
        host?.shutdown()
        host = nil
        backend?.shutdown()
        backend = nil
        tree.reset()
    }

    public func dispatch(handler: String, value: String?) { host?.dispatch(handler, value: value) }

    /// Hot reload of `ui.js`: fresh context, revisions continue, windows stay open.
    public func reloadScript() {
        guard let host, let script = try? String(contentsOf: bundle.scriptURL, encoding: .utf8) else { return }
        let rev = host.revision
        let nextCall = host.shutdown()
        startHost(script, startRev: rev, firstCallID: nextCall)
    }

    public func restartBackend() { backend?.restartAfterRequests() }

    public func update(_ bundle: AppBundle) { self.bundle = bundle }

    // MARK: -

    private func startBackend() {
        guard let spec = bundle.manifest.backend else { return }
        backend = BackendChannel(
            config: BackendConfig(
                appID: bundle.manifest.id, command: spec.exec, directory: bundle.directory,
                dataDirectory: dataRoot.appendingPathComponent(bundle.manifest.id.rawValue),
                language: language().rawValue, idle: TimeInterval(spec.idle)),
            shell: capabilities(from: .backend), log: log)
    }

    private func capabilities(from caller: ShellCapabilities.Caller)
        -> @Sendable (String, Data) -> Result<Data, CallFailure>
    {
        let shell = ShellCapabilities(appID: bundle.manifest.id, secrets: secrets)
        return { shell.handle($0, params: $1, from: caller) }
    }

    private func startHost(_ script: String, startRev: Int, firstCallID: Int) {
        let appID = bundle.manifest.id
        let backend = backend
        let ui = capabilities(from: .ui)
        nonisolated(unsafe) let defaults = defaults  // UserDefaults is documented thread-safe
        let prefix = "wisploom.app.\(appID.rawValue)."
        let log = log
        let services = HostServices(
            call: { id, method, params, reply in
                if method.hasPrefix("shell.") {
                    switch ui(method, params) {
                    case .success(let result): reply(.result(result))
                    case .failure(let failure): reply(.failure(code: failure.code, message: failure.message))
                    }
                } else if let backend {
                    backend.call(id: id, method: method, params: params, reply: reply)
                } else {
                    reply(.failure(code: "no_backend", message: "\(appID.rawValue) has no backend"))
                }
            },
            cancel: { backend?.cancel(id: $0) },
            setting: { defaults.string(forKey: prefix + $0) },
            setSetting: { defaults.set($1, forKey: prefix + $0) },
            log: { log("[\(appID.rawValue)] \($0)") })
        let host = JSHost(
            appID: appID, script: script, startRev: startRev, firstCallID: firstCallID, services: services)
        self.host = host
        // Old hosts' leftover patches carry lower revs than the new host's, so the tree drops them.
        Task { [weak self] in
            for await patch in host.patches { self?.apply(patch, from: host) }
        }
    }

    private func apply(_ patch: UIPatch, from source: JSHost) {
        do {
            try tree.apply(patch)
        } catch {
            log("[\(bundle.manifest.id.rawValue)] patch \(patch.rev) rejected (\(error)); requesting full replace")
            source.lifecycle("resync")
        }
    }
}
