/// A menu-bar entry an app registers from its page.
public struct AppCommand: Sendable, Hashable, Decodable {
    public let id: String
    public let menu: String
    public let title: String
    public let shortcut: Shortcut?
    public let isEnabled: Bool

    private enum CodingKeys: String, CodingKey { case id, menu, title, shortcut, disabled }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        menu = try c.decode(String.self, forKey: .menu)
        title = try c.decode(String.self, forKey: .title)
        shortcut = try c.decodeIfPresent(String.self, forKey: .shortcut).flatMap(Shortcut.init)
        isEnabled = !(try c.decodeIfPresent(Bool.self, forKey: .disabled) ?? false)
    }
}
