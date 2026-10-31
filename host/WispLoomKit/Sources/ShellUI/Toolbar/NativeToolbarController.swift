import AppKit
import ShellCore

/// Turns a page's `ToolbarSpec` into real AppKit controls. It knows no app: item ids, symbols and text come
/// from the page and clicks go back as ids (docs/06-native-toolbar.md §2).
@MainActor
public final class NativeToolbarController: NSObject {
    private let onAction: (String) -> Void
    private let onSearch: (String) -> Void
    private weak var window: NSWindow?
    private var spec = ToolbarSpec()
    private var items: [NSToolbarItem.Identifier: ToolbarItem] = [:]
    private var leadingIDs: Set<String> = []
    private var searchText = ""

    public init(onAction: @escaping (String) -> Void, onSearch: @escaping (String) -> Void) {
        self.onAction = onAction
        self.onSearch = onSearch
        super.init()
    }

    /// Installs the toolbar (empty until a spec arrives) so every main window has the same titlebar height.
    public func install(on window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        window.toolbarStyle = .unified
        window.titleVisibility = .visible
        rebuild()
    }

    /// A new spec replaces the old one; only a structural change rebuilds the toolbar, so typing in the
    /// search field never resets it. Enabled flags are applied in place.
    public func apply(_ next: ToolbarSpec) {
        guard next != spec else { return }
        let rebuilds = structure(of: next) != structure(of: spec)
        spec = next
        if rebuilds || window?.toolbar == nil {
            rebuild()
        } else {
            updateEnabled()
        }
    }

    private func rebuild() {
        guard let window else { return }
        items = [:]
        leadingIDs = Set(spec.leading.map(\.id))
        for item in spec.leading + spec.trailing { items[Self.identifier(for: item.id)] = item }
        let toolbar = NSToolbar(identifier: "wisp.windowToolbar")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconOnly
        toolbar.sizeMode = .regular
        window.toolbar = toolbar
    }

    /// Everything that requires new AppKit controls; `disabled` is deliberately absent.
    private func structure(of spec: ToolbarSpec) -> [String] {
        let key: (ToolbarItem) -> String = { item in
            let menu = item.menu.map { "\($0.id)|\($0.title)|\($0.destructive)" }.joined(separator: ";")
            let fields = [item.symbol, item.title, item.help, item.placeholder].map { $0 ?? "" }
            return "\(item.kind)|" + ([item.id] + fields + [menu]).joined(separator: "|")
        }
        return spec.leading.map(key) + ["-"] + spec.trailing.map(key)
    }

    private func updateEnabled() {
        guard let toolbar = window?.toolbar else { return }
        for control in toolbar.items {
            guard let item = items[control.itemIdentifier] else { continue }
            control.isEnabled = item.isEnabled
            guard let menu = (control as? NSMenuToolbarItem)?.menu else { continue }
            for (index, entry) in item.menu.enumerated() where index < menu.items.count {
                menu.items[index].isEnabled = entry.isEnabled
            }
        }
    }

    private static func identifier(for id: String) -> NSToolbarItem.Identifier {
        NSToolbarItem.Identifier("wisp.item.\(id)")
    }

    private func makeItem(_ item: ToolbarItem, identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        // AppKit only puts items at the leading edge when they are marked navigational; otherwise every
        // item collects at the trailing edge.
        switch item.kind {
        case .search:
            let search = NSSearchToolbarItem(itemIdentifier: identifier)
            search.searchField.placeholderString = item.placeholder
            search.searchField.stringValue = searchText
            search.searchField.delegate = self
            search.label = item.help ?? item.placeholder ?? "Search"
            search.paletteLabel = search.label
            search.toolTip = item.help
            search.isEnabled = item.isEnabled
            search.isNavigational = leadingIDs.contains(item.id)
            return search
        case .menu:
            let control = NSMenuToolbarItem(itemIdentifier: identifier)
            control.image = image(for: item)
            control.label = label(for: item)
            control.paletteLabel = control.label
            control.toolTip = item.help
            control.menu = makeMenu(item.menu)
            control.showsIndicator = true
            control.isEnabled = item.isEnabled
            control.isNavigational = leadingIDs.contains(item.id)
            return control
        case .button, .sidebar:
            let control = NSToolbarItem(itemIdentifier: identifier)
            control.image = image(for: item)
            control.label = label(for: item)
            control.paletteLabel = control.label
            control.toolTip = item.help
            control.isBordered = true
            control.target = self
            control.action = #selector(buttonClicked(_:))
            control.isEnabled = item.isEnabled
            control.isNavigational = leadingIDs.contains(item.id)
            return control
        }
    }

    private func label(for item: ToolbarItem) -> String {
        item.title ?? item.help ?? (item.kind == .sidebar ? "Toggle Sidebar" : item.id)
    }

    private func image(for item: ToolbarItem) -> NSImage? {
        let name = item.symbol ?? (item.kind == .sidebar ? "sidebar.left" : nil)
        return name.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: label(for: item)) }
    }

    private func makeMenu(_ entries: [ToolbarMenuItem]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for entry in entries {
            let item = NSMenuItem(title: entry.title, action: #selector(menuItemClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.id
            item.isEnabled = entry.isEnabled
            menu.addItem(item)
        }
        return menu
    }

    @objc private func buttonClicked(_ sender: NSToolbarItem) {
        guard let item = items[sender.itemIdentifier] else { return }
        onAction(item.id)
    }

    @objc private func menuItemClicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        onAction(id)
    }
}

extension NativeToolbarController: NSToolbarDelegate {
    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        let leading = spec.leading.map { Self.identifier(for: $0.id) }
        let trailing = spec.trailing.map { Self.identifier(for: $0.id) }
        // The flexible space keeps trailing items on the right; even an empty spec keeps one so
        // the window keeps the same titlebar height.
        return leading + [.flexibleSpace] + trailing
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace] + (spec.leading + spec.trailing).map { Self.identifier(for: $0.id) }
    }

    public func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let item = items[identifier] else { return nil }
        return makeItem(item, identifier: identifier)
    }
}

extension NativeToolbarController: NSSearchFieldDelegate {
    public func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSSearchField else { return }
        searchText = field.stringValue
        onSearch(searchText)
    }
}
