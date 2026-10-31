import AppKit

/// One tab of a settings window; the shell's own settings and every app's use the same structure.
public struct SettingsPane {
    public let id: String
    public let title: String
    public let symbol: String
    public let content: NSViewController

    public init(id: String, title: String, symbol: String, content: NSViewController) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.content = content
    }
}

/// Toolbar-style tabs; the window title follows the selected pane.
final class SettingsTabController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        view.window?.title = tabViewItem?.label ?? ""
    }
}
