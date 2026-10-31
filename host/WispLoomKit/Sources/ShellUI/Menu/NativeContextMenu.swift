import AppKit
import ShellCore

/// The page's right-click menu. AppKit owns tracking, Escape/click-away dismissal and dark mode; the page
/// only sends item ids/titles/flags and gets the selected id back.
@MainActor
public final class NativeContextMenu: NSObject {
    private var onSelect: ((String) -> Void)?

    public override init() { super.init() }

    public func show(_ entries: [ToolbarMenuItem], at point: NSPoint, onSelect: @escaping (String) -> Void) {
        guard !entries.isEmpty else { return }
        self.onSelect = onSelect
        let menu = NativeMenuFactory.make(entries, target: self, action: #selector(clicked(_:)))
        menu.popUp(positioning: nil, at: point, in: nil)
        self.onSelect = nil
    }

    @objc private func clicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        onSelect?(id)
    }
}
