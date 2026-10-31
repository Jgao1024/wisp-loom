import Observation

@MainActor
@Observable
public final class ShellState {
    public internal(set) var apps: [AppDescriptor]
    public internal(set) var windows: [WindowInstance] = []
    public internal(set) var launcherStyle: LauncherStyle
    public internal(set) var hotKey: HotKey
    public internal(set) var language: Language

    public init(
        apps: [AppDescriptor], launcherStyle: LauncherStyle = .grid, hotKey: HotKey = .default,
        language: Language = .default
    ) {
        self.apps = apps
        self.launcherStyle = launcherStyle
        self.hotKey = hotKey
        self.language = language
    }

    public func app(for appID: AppID) -> AppDescriptor? { apps.first { $0.id == appID } }

    public func window(for appID: AppID, kind: WindowInstance.Kind = .main) -> WindowInstance? {
        let candidates = windows.filter { $0.appID == appID && $0.kind == kind }
        return candidates.first(where: \.isKey) ?? candidates.last
    }

    /// The app the menu bar should show: the key window's, else the most recent one's.
    public var activeAppID: AppID? { (windows.first(where: \.isKey) ?? windows.last)?.appID }

    func apply(_ event: WindowEvent) {
        switch event {
        case .opened(let window):
            guard !windows.contains(where: { $0.id == window.id }) else { return }
            windows.append(window)
        case .closed(let id):
            windows.removeAll { $0.id == id }
        case .focused(let id):
            for index in windows.indices {
                windows[index].isKey = windows[index].id == id
            }
        }
    }
}
