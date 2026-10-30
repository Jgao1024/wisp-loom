import AppKit
import ShellCore

@MainActor
public final class WindowManager: NSObject, WindowManaging, NSWindowDelegate {
    public let events: AsyncStream<WindowEvent>
    public var contentProvider: ((AppDescriptor) -> NSViewController)?

    private let continuation: AsyncStream<WindowEvent>.Continuation
    private let factory: WindowFactory
    private var windows: [WindowID: NSWindow] = [:]

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
        windows[instance.id] = window
        continuation.yield(.opened(instance))
        activate(window)
    }

    public func focusWindow(_ id: WindowID) {
        guard let window = windows[id] else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        activate(window)
    }

    public func closeAllWindows() {
        for window in Array(windows.values) { window.close() }
    }

    public func windowDidBecomeKey(_ notification: Notification) {
        if let id = id(of: notification.object) { continuation.yield(.focused(id)) }
    }

    public func windowWillClose(_ notification: Notification) {
        guard let id = id(of: notification.object) else { return }
        windows[id] = nil
        continuation.yield(.closed(id))
    }

    private func activate(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func id(of object: Any?) -> WindowID? {
        windows.first { $0.value === object as? NSWindow }?.key
    }
}
