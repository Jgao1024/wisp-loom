public struct WindowInstance: Identifiable, Sendable, Hashable {
    public let id: WindowID
    public let appID: AppID
    public var isKey: Bool

    public init(id: WindowID = WindowID(), appID: AppID, isKey: Bool = false) {
        self.id = id
        self.appID = appID
        self.isKey = isKey
    }
}
