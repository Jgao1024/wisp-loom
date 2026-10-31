import AppKit
import AppRuntime
import ShellCore
import ShellPlatform
import ShellUI
import SwiftUI

/// Knows the installed apps and owns the running ones. Sessions are created on first use and
/// released with their last window.
@MainActor
final class AppRegistry {
    private let state: ShellState
    private let secrets = KeychainSecretStore()
    private let dataRoot: URL
    private let log: @Sendable (String) -> Void
    private(set) var bundles: [AppBundle] = []
    private var sessions: [AppID: AppSession] = [:]

    init(state: ShellState, dataRoot: URL, log: @escaping @Sendable (String) -> Void) {
        self.state = state
        self.dataRoot = dataRoot
        self.log = log
    }

    func descriptors(for language: Language) -> [AppDescriptor] {
        bundles.map { AppDescriptor($0.manifest, language: language) }
    }

    func load(from roots: [URL]) -> [AppDescriptor] {
        bundles = AppCatalog.scan(roots, log: log)
        for bundle in bundles { sessions[bundle.manifest.id]?.update(bundle) }
        return descriptors(for: state.language)
    }

    /// Dev-time reload of one running app; apps without a session pick the change up when they start.
    func apply(_ change: AppChange) {
        switch change {
        case .script(let id): sessions[id]?.reloadScript()
        case .backend(let id): sessions[id]?.restartBackend()
        case .manifest: break
        }
    }

    /// Window content for an app; the first window starts the app.
    func makeContent(for app: AppDescriptor) -> NSViewController? {
        guard let session = session(for: app.id) else { return nil }
        session.retain()
        let events = UIEvents { [weak session] handler, value in session?.dispatch(handler: handler, value: value) }
        return NSHostingController(rootView: AppWindowView(state: state, tree: session.tree, events: events))
    }

    func windowClosed(_ id: AppID) { sessions[id]?.release() }

    func tree(for id: AppID) -> UITree? { sessions[id]?.tree }

    func dispatch(_ id: AppID, handler: String) { sessions[id]?.dispatch(handler: handler, value: nil) }

    /// Panes the app declared with `<Settings>`. The settings window keeps the app running like any other
    /// window does, so it takes a reference only when it will really open.
    func settingsPanes(for app: AppDescriptor) -> [SettingsPane] {
        guard let session = sessions[app.id] else { return [] }
        let nodes = session.tree.nodes(ofType: "Pane")
        guard !nodes.isEmpty else { return [] }
        session.retain()
        let events = UIEvents { [weak session] handler, value in session?.dispatch(handler: handler, value: value) }
        return nodes.map { node in
            SettingsPane(
                id: node.id, title: node.string("title") ?? "", symbol: node.string("symbol") ?? "gearshape",
                content: NSHostingController(rootView: PaneView(node: node, state: state, events: events)))
        }
    }

    private func session(for id: AppID) -> AppSession? {
        if let existing = sessions[id] { return existing }
        guard let bundle = bundles.first(where: { $0.manifest.id == id }) else { return nil }
        let state = state
        let session = AppSession(
            bundle: bundle, dataRoot: dataRoot, language: { state.language }, secrets: secrets, log: log)
        sessions[id] = session
        return session
    }
}
