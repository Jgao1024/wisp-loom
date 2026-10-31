import ShellCore

@MainActor
final class FakeWindowManager: WindowManaging {
    let events: AsyncStream<WindowEvent>
    private let continuation: AsyncStream<WindowEvent>.Continuation

    private(set) var opened: [AppID] = []
    private(set) var settingsOpened: [AppID] = []
    private(set) var closedApps: [AppID] = []
    private(set) var focused: [WindowID] = []
    private(set) var didCloseAll = false

    init() { (events, continuation) = AsyncStream.makeStream() }

    func openWindow(for app: AppDescriptor) { opened.append(app.id) }
    func openSettingsWindow(for app: AppDescriptor) { settingsOpened.append(app.id) }
    func closeWindows(of appID: AppID) { closedApps.append(appID) }
    func focusWindow(_ id: WindowID) { focused.append(id) }
    func closeAllWindows() { didCloseAll = true }

    func send(_ event: WindowEvent) { continuation.yield(event) }
}

@MainActor
final class FakePresenter: ShellPresenting {
    var isLauncherVisible = false
    private(set) var settingsShown = 0

    func showLauncher() { isLauncherVisible = true }
    func hideLauncher() { isLauncherVisible = false }
    func showSettings() { settingsShown += 1 }
}

@MainActor
final class FakeHotKeys: HotKeyRegistering {
    var rejects = false
    private(set) var registered: HotKey?

    func register(_ hotKey: HotKey, handler: @escaping @MainActor () -> Void) -> Bool {
        guard !rejects else { return false }
        registered = hotKey
        return true
    }

    func unregister() { registered = nil }
}
