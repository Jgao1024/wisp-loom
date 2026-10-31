import AppKit
import ShellCore

/// The only place NSWindow / NSPanel instances are created.
@MainActor
public final class WindowFactory {
    public init() {}

    public func makeLauncherPanel(content: NSViewController) -> NSPanel {
        let panel = LauncherPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = content
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        return panel
    }

    public func makeAppWindow(for app: AppDescriptor, content: NSViewController) -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: app.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = app.name
        window.minSize = app.minimumSize
        window.contentViewController = content
        window.setContentSize(app.defaultSize)
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    /// A small fixed-width window whose title follows the page (`document.title`); size comes from the page.
    public func makeSettingsWindow(for app: AppDescriptor, content: NSViewController) -> NSWindow {
        let window = NSWindow(contentViewController: content)
        window.styleMask = [.titled, .closable]
        window.title = app.name
        window.setContentSize(CGSize(width: 560, height: 420))
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    /// The shell's own settings: the same toolbar-tab structure every settings window used before the web switch.
    public func makeSettingsWindow(panes: [SettingsPane]) -> NSWindow {
        let tabs = SettingsTabController()
        tabs.tabStyle = .toolbar
        for pane in panes {
            let item = NSTabViewItem(viewController: pane.content)
            item.label = pane.title
            item.identifier = pane.id
            item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
            tabs.addTabViewItem(item)
        }
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.title = panes.first?.title ?? ""
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
