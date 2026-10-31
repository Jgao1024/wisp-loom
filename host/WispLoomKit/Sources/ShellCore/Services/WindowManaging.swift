@MainActor
public protocol WindowManaging: AnyObject {
    var events: AsyncStream<WindowEvent> { get }

    func openWindow(for app: AppDescriptor)
    func openSettingsWindow(for app: AppDescriptor)
    func closeWindows(of appID: AppID)
    func focusWindow(_ id: WindowID)
    func closeAllWindows()
}
