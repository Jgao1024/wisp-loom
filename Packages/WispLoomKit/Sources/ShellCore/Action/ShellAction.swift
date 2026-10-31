public enum ShellAction: Sendable, Hashable {
    case openApp(AppID)
    case openAppSettings(AppID)
    /// "Quit X" in an app's menu: closes that app's windows, not Wisp Loom.
    case closeApp(AppID)
    case showLauncher
    case hideLauncher
    case toggleLauncher
    case openSettings
    case setLauncherStyle(LauncherStyle)
    case setHotKey(HotKey)
    case setLanguage(Language)
    case quit
}
