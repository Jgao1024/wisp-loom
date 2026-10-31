public struct WindowInstance: Identifiable, Sendable, Hashable {
    public let id: WindowID
    public enum Kind: Sendable, Hashable { case main, settings }

    public let appID: AppID
    public let kind: Kind
    public var isKey: Bool

    public init(id: WindowID = WindowID(), appID: AppID, kind: Kind = .main, isKey: Bool = false) {
        self.id = id
        self.appID = appID
        self.kind = kind
        self.isKey = isKey
    }
}
