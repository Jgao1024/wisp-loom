import AppKit
import ShellCore

/// Builds a native menu from page-declared entries. Every item carries the page's id in `representedObject`;
/// clicking reports only that id. Shared by toolbar menus and context menus.
@MainActor
enum NativeMenuFactory {
    static func make(_ entries: [ToolbarMenuItem], target: AnyObject, action: Selector) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for entry in entries {
            let item = NSMenuItem(title: entry.title, action: action, keyEquivalent: "")
            item.target = target
            item.representedObject = entry.id
            item.isEnabled = entry.isEnabled
            if entry.destructive {
                item.attributedTitle = NSAttributedString(
                    string: entry.title, attributes: [.foregroundColor: NSColor.systemRed])
            }
            menu.addItem(item)
        }
        return menu
    }
}
