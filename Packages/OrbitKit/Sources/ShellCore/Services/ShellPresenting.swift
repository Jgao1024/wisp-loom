@MainActor
public protocol ShellPresenting: AnyObject {
    var isLauncherVisible: Bool { get }

    func showLauncher()
    func hideLauncher()
    func showSettings()
}
