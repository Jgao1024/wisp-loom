import Observation

@MainActor
@Observable
public final class ShellState {
    public let apps: [AppDescriptor]
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

    public func window(for appID: AppID) -> WindowInstance? {
        let candidates = windows.filter { $0.appID == appID }
        return candidates.first(where: \.isKey) ?? candidates.last
    }

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
