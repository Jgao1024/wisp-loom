import AppKit

/// Menu bar icon: left click runs `onClick`, right click (or control-click) pops up the menu.
@MainActor
public final class StatusItemController: NSObject {
    public struct Entry: Sendable {
        let title: String
        let action: @MainActor @Sendable () -> Void

        public init(_ title: String, action: @escaping @MainActor @Sendable () -> Void) {
            self.title = title
            self.action = action
        }
    }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let onClick: @MainActor () -> Void
    private let entries: () -> [Entry]
    private var current: [Entry] = []

    public init(symbolName: String, onClick: @escaping @MainActor () -> Void, entries: @escaping () -> [Entry]) {
        self.onClick = onClick
        self.entries = entries
        super.init()
        guard let button = item.button else { return }
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func clicked() {
        guard let button = item.button else { return }
        let event = NSApp.currentEvent
        guard event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true else { return onClick() }

        current = entries()
        let menu = NSMenu()
        for (index, entry) in current.enumerated() {
            let menuItem = NSMenuItem(title: entry.title, action: #selector(run(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.tag = index
            menu.addItem(menuItem)
        }
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func run(_ sender: NSMenuItem) { current[sender.tag].action() }
}
