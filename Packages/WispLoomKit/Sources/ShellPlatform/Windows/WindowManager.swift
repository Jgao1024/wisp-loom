import AppKit
import ShellCore

@MainActor
public final class WindowManager: NSObject, WindowManaging, NSWindowDelegate {
    public let events: AsyncStream<WindowEvent>
    public var contentProvider: ((AppDescriptor, WindowInstance.Kind) -> NSViewController?)?
    /// Called after each app window closes, so the owner can release what the window needed.
    public var windowDidClose: ((AppID, WindowInstance.Kind, NSViewController?) -> Void)?

    private let continuation: AsyncStream<WindowEvent>.Continuation
    private let factory: WindowFactory
    private var windows: [WindowID: (window: NSWindow, appID: AppID, kind: WindowInstance.Kind)] = [:]

    public init(factory: WindowFactory) {
        self.factory = factory
        (events, continuation) = AsyncStream.makeStream()
        super.init()
    }

    public func openWindow(for app: AppDescriptor) {
        guard let content = contentProvider?(app, .main) else { return }
        show(factory.makeAppWindow(for: app, content: content), app: app.id, kind: .main)
    }

    public func openSettingsWindow(for app: AppDescriptor) {
        guard let content = contentProvider?(app, .settings) else { return }
        show(factory.makeSettingsWindow(for: app, content: content), app: app.id, kind: .settings)
    }

    public func focusWindow(_ id: WindowID) {
        guard let window = windows[id]?.window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        activate(window)
    }

    public func closeWindows(of appID: AppID) {
        for entry in Array(windows.values) where entry.appID == appID { entry.window.close() }
    }

    public func closeAllWindows() {
        for entry in Array(windows.values) { entry.window.close() }
    }

    public func windowDidBecomeKey(_ notification: Notification) {
        guard let id = id(of: notification.object) else { return }
        enterRegular()
        continuation.yield(.focused(id))
    }

    public func windowWillClose(_ notification: Notification) {
        guard let id = id(of: notification.object), let entry = windows.removeValue(forKey: id) else { return }
        continuation.yield(.closed(id))
        windowDidClose?(entry.appID, entry.kind, entry.window.contentViewController)
        // No app windows left: drop out of the Dock and menu bar again.
        if windows.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }

    private func show(_ window: NSWindow, app: AppID, kind: WindowInstance.Kind) {
        let instance = WindowInstance(appID: app, kind: kind)
        window.delegate = self
        windows[instance.id] = (window, app, kind)
        continuation.yield(.opened(instance))
        activate(window)
    }

    private func activate(_ window: NSWindow) {
        enterRegular()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// App windows need a menu bar and Dock presence; the launcher alone does not.
    private func enterRegular() {
        guard NSApp.activationPolicy() != .regular else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    private func id(of object: Any?) -> WindowID? {
        windows.first { $0.value.window === object as? NSWindow }?.key
    }
}
