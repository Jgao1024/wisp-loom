import AppKit
import ShellCore

@MainActor
public final class WindowManager: NSObject, WindowManaging, NSWindowDelegate {
    public let events: AsyncStream<WindowEvent>
    public var contentProvider: ((AppDescriptor) -> NSViewController?)?
    /// Called after each app window closes, so the owner can release what the window needed.
    public var windowDidClose: ((AppID) -> Void)?

    private let continuation: AsyncStream<WindowEvent>.Continuation
    private let factory: WindowFactory
    private var windows: [WindowID: (window: NSWindow, appID: AppID)] = [:]

    public init(factory: WindowFactory) {
        self.factory = factory
        (events, continuation) = AsyncStream.makeStream()
        super.init()
    }

    public func openWindow(for app: AppDescriptor) {
        guard let content = contentProvider?(app) else { return }
        let instance = WindowInstance(appID: app.id)
        let window = factory.makeAppWindow(for: app, content: content)
        window.delegate = self
        windows[instance.id] = (window, app.id)
        continuation.yield(.opened(instance))
        activate(window)
    }

    public func focusWindow(_ id: WindowID) {
        guard let window = windows[id]?.window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        activate(window)
    }

    public func closeAllWindows() {
        for entry in Array(windows.values) { entry.window.close() }
    }

    public func windowDidBecomeKey(_ notification: Notification) {
        if let id = id(of: notification.object) { continuation.yield(.focused(id)) }
    }

    public func windowWillClose(_ notification: Notification) {
        guard let id = id(of: notification.object), let entry = windows.removeValue(forKey: id) else { return }
        continuation.yield(.closed(id))
        windowDidClose?(entry.appID)
    }

    private func activate(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func id(of object: Any?) -> WindowID? {
        windows.first { $0.value.window === object as? NSWindow }?.key
    }
}
