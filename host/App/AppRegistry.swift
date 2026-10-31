import AppKit
import AppRuntime
import ShellCore
import ShellUI

/// Knows the installed apps and owns the running ones. A session is created on an app's first window and
/// dropped with its last one.
@MainActor
final class AppRegistry {
    private let state: ShellState
    private let secrets = KeychainSecretStore()
    private let dataRoot: URL
    private let log: @Sendable (String) -> Void
    private(set) var bundles: [AppBundle] = []
    private var sessions: [AppID: AppSession] = [:]
    /// Called when any app's command list changes, so the menu bar can rebuild.
    var onCommandsChange: (@MainActor () -> Void)?
    var openSettings: (@MainActor (AppID) -> Void)?

    init(state: ShellState, dataRoot: URL, log: @escaping @Sendable (String) -> Void) {
        self.state = state
        self.dataRoot = dataRoot
        self.log = log
    }

    func load(from roots: [URL]) -> [AppDescriptor] {
        bundles = AppCatalog.scan(roots, log: log)
        for bundle in bundles { sessions[bundle.manifest.id]?.update(bundle) }
        return bundles.map { AppDescriptor($0.manifest, language: state.language) }
    }

    /// Dev-time change of a running app; apps without a session pick it up when they start.
    func apply(_ change: AppChange) {
        switch change {
        case .script(let id): sessions[id]?.reloadPages()
        case .backend(let id): sessions[id]?.restartBackend()
        case .manifest: break
        }
    }

    func makeContent(for app: AppDescriptor, kind: WindowInstance.Kind) -> NSViewController? {
        guard let session = session(for: app.id) else { return nil }
        return AppPageController(connection: session.connect(kind: kind))
    }

    /// Releases the window's link; the app's last window takes the session (and backend) with it.
    func windowClosed(_ id: AppID, content: NSViewController?) {
        (content as? AppPageController)?.tearDown()
        if let session = sessions[id], !session.isRunning { sessions[id] = nil }
    }

    func commands(for id: AppID) -> [AppCommand] { sessions[id]?.commands ?? [] }

    func fire(_ command: String, in id: AppID) { sessions[id]?.fire(command: command) }

    private func session(for id: AppID) -> AppSession? {
        if let existing = sessions[id] { return existing }
        guard let bundle = bundles.first(where: { $0.manifest.id == id }) else { return nil }
        let state = state
        let session = AppSession(
            bundle: bundle, dataRoot: dataRoot, language: { state.language }, secrets: secrets, log: log)
        session.onCommandsChange = { [weak self] in self?.onCommandsChange?() }
        session.onOpenSettings = { [weak self] in self?.openSettings?(id) }
        sessions[id] = session
        return session
    }
}
