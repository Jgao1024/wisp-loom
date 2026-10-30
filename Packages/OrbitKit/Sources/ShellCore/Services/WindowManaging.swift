@MainActor
public protocol WindowManaging: AnyObject {
    var events: AsyncStream<WindowEvent> { get }

    func openWindow(for app: AppDescriptor)
    func focusWindow(_ id: WindowID)
    func closeAllWindows()
}
