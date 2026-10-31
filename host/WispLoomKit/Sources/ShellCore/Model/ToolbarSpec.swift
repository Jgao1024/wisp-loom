/// A window toolbar described by the page. The page only names items and handlers; every control and its
/// appearance is chosen by the host (docs/06-native-toolbar.md §3).
public struct ToolbarMenuItem: Sendable, Equatable, Decodable {
    public let id: String
    public let title: String
    public let destructive: Bool
    public let isEnabled: Bool

    private enum CodingKeys: String, CodingKey { case id, title, destructive, disabled }

    public init(id: String, title: String, destructive: Bool = false, isEnabled: Bool = true) {
        self.id = id
        self.title = title
        self.destructive = destructive
        self.isEnabled = isEnabled
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        destructive = try container.decodeIfPresent(Bool.self, forKey: .destructive) ?? false
        isEnabled = !(try container.decodeIfPresent(Bool.self, forKey: .disabled) ?? false)
    }
}

public struct ToolbarItem: Sendable, Equatable, Decodable {
    public enum Kind: Sendable, Equatable { case button, menu, search, sidebar }

    public let id: String
    public let symbol: String?
    public let title: String?
    public let help: String?
    public let isEnabled: Bool
    public let menu: [ToolbarMenuItem]
    public let search: Bool
    public let sidebar: Bool
    public let placeholder: String?

    private enum CodingKeys: String, CodingKey {
        case id, symbol, title, help, disabled, menu, search, sidebar, placeholder
    }

    public init(
        id: String, symbol: String? = nil, title: String? = nil, help: String? = nil, isEnabled: Bool = true,
        menu: [ToolbarMenuItem] = [], search: Bool = false, sidebar: Bool = false, placeholder: String? = nil
    ) {
        self.id = id
        self.symbol = symbol
        self.title = title
        self.help = help
        self.isEnabled = isEnabled
        self.menu = menu
        self.search = search
        self.sidebar = sidebar
        self.placeholder = placeholder
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        help = try container.decodeIfPresent(String.self, forKey: .help)
        isEnabled = !(try container.decodeIfPresent(Bool.self, forKey: .disabled) ?? false)
        menu = try container.decodeIfPresent([ToolbarMenuItem].self, forKey: .menu) ?? []
        search = try container.decodeIfPresent(Bool.self, forKey: .search) ?? false
        sidebar = try container.decodeIfPresent(Bool.self, forKey: .sidebar) ?? false
        placeholder = try container.decodeIfPresent(String.self, forKey: .placeholder)
    }

    public var kind: Kind { sidebar ? .sidebar : (search ? .search : (menu.isEmpty ? .button : .menu)) }
}

public struct ToolbarSpec: Sendable, Equatable, Decodable {
    public let leading: [ToolbarItem]
    public let trailing: [ToolbarItem]

    private enum CodingKeys: String, CodingKey { case leading, trailing }

    public init(leading: [ToolbarItem] = [], trailing: [ToolbarItem] = []) {
        self.leading = leading
        self.trailing = trailing
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        leading = try container.decodeIfPresent([ToolbarItem].self, forKey: .leading) ?? []
        trailing = try container.decodeIfPresent([ToolbarItem].self, forKey: .trailing) ?? []
    }
}
