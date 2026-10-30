public enum ShellAction: Sendable, Hashable {
    case openApp(AppID)
    case showLauncher
    case hideLauncher
    case toggleLauncher
    case openSettings
    case setLauncherStyle(LauncherStyle)
    case setHotKey(HotKey)
    case setLanguage(Language)
    case quit
}
