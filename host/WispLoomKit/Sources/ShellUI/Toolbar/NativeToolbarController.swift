import AppKit
import ShellCore

/// Turns a page's `ToolbarSpec` into real AppKit controls. It knows no app: item ids, symbols and text come
/// from the page and clicks go back as ids (docs/06-native-toolbar.md §2).
@MainActor
public final class NativeToolbarController: NSObject {
    private let onAction: (String) -> Void
    private let onSearch: (String) -> Void
    private let onTab: (String) -> Void
    private weak var window: NSWindow?
    private var spec = ToolbarSpec()
    private var items: [NSToolbarItem.Identifier: ToolbarItem] = [:]
    private var leadingIDs: Set<String> = []
    private var searchText = ""
    private static let tabPrefix = "wisp.tab."

    public init(
        onAction: @escaping (String) -> Void, onSearch: @escaping (String) -> Void,
        onTab: @escaping (String) -> Void = { _ in }
    ) {
        self.onAction = onAction
        self.onSearch = onSearch
        self.onTab = onTab
        super.init()
    }

    /// Installs the toolbar (empty until a spec arrives) so every window has the same titlebar height.
    /// Settings windows pass `.preference` so the tabs get their own row below the native titlebar.
    public func install(on window: NSWindow, style: NSWindow.ToolbarStyle = .unified) {
        guard self.window !== window else { return }
        self.window = window
        window.toolbarStyle = style
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
            updateSelection()
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
        toolbar.sizeMode = .regular
        window.toolbar = toolbar
        toolbar.displayMode = spec.tabs.isEmpty ? .iconOnly : .iconAndLabel
        toolbar.selectedItemIdentifier = selectedTabIdentifier
    }

    /// Everything that requires new AppKit controls; `disabled` and tab `selected` are deliberately absent.
    private func structure(of spec: ToolbarSpec) -> [String] {
        let key: (ToolbarItem) -> String = { item in
            let menu = item.menu.map { "\($0.id)|\($0.title)|\($0.destructive)" }.joined(separator: ";")
            let fields = [item.symbol, item.title, item.help, item.placeholder].map { $0 ?? "" }
            return "\(item.kind)|" + ([item.id] + fields + [menu]).joined(separator: "|")
        }
        let tabs = spec.tabs.map { "\($0.id)|\($0.title)|\($0.symbol ?? "")" }.joined(separator: ";")
        return spec.leading.map(key) + ["-"] + spec.trailing.map(key) + ["tabs", tabs]
    }

    private func updateSelection() {
        guard let toolbar = window?.toolbar, !spec.tabs.isEmpty else { return }
        toolbar.selectedItemIdentifier = selectedTabIdentifier
    }

    private var selectedTabIdentifier: NSToolbarItem.Identifier? {
        guard let tab = spec.tabs.first(where: \.selected) else { return nil }
        return Self.tabIdentifier(for: tab.id)
    }

    private static func tabIdentifier(for id: String) -> NSToolbarItem.Identifier {
        NSToolbarItem.Identifier(tabPrefix + id)
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
        NativeMenuFactory.make(entries, target: self, action: #selector(menuItemClicked(_:)))
    }

    /// One settings pane tab: a native toolbar item with an SF Symbol and its title. Selection is drawn by
    /// `NSToolbar.selectedItemIdentifier`, the same mechanism the system tab-style settings windows use.
    private func makeTabItem(_ tab: ToolbarTab) -> NSToolbarItem {
        let identifier = Self.tabIdentifier(for: tab.id)
        let control = NSToolbarItem(itemIdentifier: identifier)
        if let symbol = tab.symbol {
            control.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tab.title)
        }
        control.label = tab.title
        control.paletteLabel = tab.title
        control.toolTip = tab.title
        control.isBordered = false
        control.target = self
        control.action = #selector(tabClicked(_:))
        control.isNavigational = true
        return control
    }

    @objc private func buttonClicked(_ sender: NSToolbarItem) {
        guard let item = items[sender.itemIdentifier] else { return }
        onAction(item.id)
    }

    @objc private func menuItemClicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        onAction(id)
    }

    @objc private func tabClicked(_ sender: NSToolbarItem) {
        let prefix = Self.tabPrefix
        let id = String(sender.itemIdentifier.rawValue.dropFirst(prefix.count))
        guard spec.tabs.contains(where: { $0.id == id }) else { return }
        onTab(id)
    }
}

extension NativeToolbarController: NSToolbarDelegate {
    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        let leading = spec.leading.map { Self.identifier(for: $0.id) }
        let trailing = spec.trailing.map { Self.identifier(for: $0.id) }
        // The flexible space keeps trailing items on the right; tabs sit between two flexible spaces so a
        // tabs-only settings toolbar is centred. Even an empty spec keeps one space for a stable titlebar.
        guard !spec.tabs.isEmpty else { return leading + [.flexibleSpace] + trailing }
        return leading + [.flexibleSpace] + spec.tabs.map { Self.tabIdentifier(for: $0.id) } + [.flexibleSpace]
            + trailing
    }

    public func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        spec.tabs.map { Self.tabIdentifier(for: $0.id) }
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace] + spec.tabs.map { Self.tabIdentifier(for: $0.id) }
            + (spec.leading + spec.trailing).map { Self.identifier(for: $0.id) }
    }

    public func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        if identifier.rawValue.hasPrefix(Self.tabPrefix),
            let tab = spec.tabs.first(where: { Self.tabIdentifier(for: $0.id) == identifier })
        {
            return makeTabItem(tab)
        }
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
