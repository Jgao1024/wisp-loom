import Foundation

@MainActor
public final class ShellController {
    public let state: ShellState

    private let windows: any WindowManaging
    private let presenter: any ShellPresenting
    private let hotKeys: any HotKeyRegistering
    private let defaults: UserDefaults
    private let onQuit: @MainActor () -> Void
    private var eventTask: Task<Void, Never>?

    public init(
        state: ShellState,
        windows: any WindowManaging,
        presenter: any ShellPresenting,
        hotKeys: any HotKeyRegistering,
        defaults: UserDefaults = .standard,
        onQuit: @escaping @MainActor () -> Void
    ) {
        self.state = state
        self.windows = windows
        self.presenter = presenter
        self.hotKeys = hotKeys
        self.defaults = defaults
        self.onQuit = onQuit
    }

    public func start() {
        guard eventTask == nil else { return }
        _ = register(state.hotKey)
        eventTask = Task { [weak self] in
            guard let events = self?.windows.events else { return }
            for await event in events {
                self?.state.apply(event)
            }
        }
    }

    public func stop() {
        eventTask?.cancel()
        eventTask = nil
        hotKeys.unregister()
        windows.closeAllWindows()
    }

    public func dispatch(_ action: ShellAction) {
        switch action {
        case .openApp(let id):
            guard let app = state.app(for: id) else { return }
            presenter.hideLauncher()
            if let window = state.window(for: id) {
                windows.focusWindow(window.id)
            } else {
                windows.openWindow(for: app)
            }
        case .openAppSettings(let id):
            guard let app = state.app(for: id), app.hasSettings else { return }
            presenter.hideLauncher()
            if let window = state.window(for: id, kind: .settings) {
                windows.focusWindow(window.id)
            } else {
                windows.openSettingsWindow(for: app)
            }
        case .closeApp(let id):
            windows.closeWindows(of: id)
        case .showLauncher:
            presenter.showLauncher()
        case .hideLauncher:
            presenter.hideLauncher()
        case .toggleLauncher:
            dispatch(presenter.isLauncherVisible ? .hideLauncher : .showLauncher)
        case .openSettings:
            presenter.hideLauncher()
            presenter.showSettings()
        case .setLauncherStyle(let style):
            state.launcherStyle = style
            style.store(in: defaults)
        case .setHotKey(let hotKey):
            guard register(hotKey) else {
                _ = register(state.hotKey)
                return
            }
            state.hotKey = hotKey
            hotKey.store(in: defaults)
        case .setLanguage(let language):
            state.language = language
            state.apps = state.apps.map { $0.localized(language) }
            language.store(in: defaults)
        case .quit:
            onQuit()
        }
    }

    /// Replaces the launcher's apps (initial scan, manifest hot reload).
    public func setApps(_ apps: [AppDescriptor]) {
        state.apps = apps.map { $0.localized(state.language) }
    }

    private func register(_ hotKey: HotKey) -> Bool {
        hotKeys.register(hotKey) { [weak self] in self?.dispatch(.toggleLauncher) }
    }
}
