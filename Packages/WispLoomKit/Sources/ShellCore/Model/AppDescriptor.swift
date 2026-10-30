import CoreGraphics

public struct AppDescriptor: Identifiable, Sendable, Hashable {
    public let id: AppID
    public let name: String
    public let symbolName: String
    public let tint: AppTint
    public let category: String
    public let keywords: [String]
    public let defaultSize: CGSize
    public let minimumSize: CGSize

    public init(
        id: AppID,
        name: String,
        symbolName: String,
        tint: AppTint,
        category: String,
        keywords: [String] = [],
        defaultSize: CGSize = CGSize(width: 900, height: 600),
        minimumSize: CGSize = CGSize(width: 480, height: 320)
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.tint = tint
        self.category = category
        self.keywords = keywords
        self.defaultSize = defaultSize
        self.minimumSize = minimumSize
    }
}
