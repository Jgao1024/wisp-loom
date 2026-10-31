import AppKit
import ShellCore

@MainActor
public final class ShellPresenter: NSObject, ShellPresenting, NSWindowDelegate {
    public var launcherContent: (() -> NSViewController)?
    public var settingsPanes: (() -> [SettingsPane])?

    private let factory: WindowFactory
    private var launcher: NSPanel?
    private var settings: NSWindow?

    public init(factory: WindowFactory) { self.factory = factory }

    public var isLauncherVisible: Bool { launcher != nil }

    public func showLauncher() {
        guard launcher == nil, let content = launcherContent?() else { return }
        let panel = factory.makeLauncherPanel(content: content)
        panel.delegate = self
        panel.setContentSize(content.view.fittingSize)
        panel.setFrameOrigin(Self.origin(for: panel.frame.size))
        launcher = panel
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    public func hideLauncher() {
        launcher?.delegate = nil
        launcher?.orderOut(nil)
        launcher = nil
    }

    public func showSettings() {
        if settings == nil, let panes = settingsPanes?(), !panes.isEmpty {
            settings = factory.makeSettingsWindow(panes: panes)
        }
        NSApp.activate()
        settings?.makeKeyAndOrderFront(nil)
    }

    public func windowDidResignKey(_ notification: Notification) { hideLauncher() }

    /// Centered on the screen under the pointer.
    private static func origin(for size: CGSize) -> CGPoint {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? .main
        let frame = screen?.visibleFrame ?? .zero
        return CGPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2)
    }
}
