import CoreGraphics

/// What the launcher and window manager need to know about an app, resolved for one language.
public struct AppDescriptor: Identifiable, Sendable, Hashable {
    public let id: AppID
    public let name: String
    public let symbolName: String
    public let tint: AppTint
    public let category: String
    public let keywords: [String]
    public let defaultSize: CGSize
    public let minimumSize: CGSize
    public let hasSettings: Bool
    private let manifest: Manifest?

    public init(
        id: AppID,
        name: String,
        symbolName: String,
        tint: AppTint,
        category: String,
        keywords: [String] = [],
        defaultSize: CGSize = CGSize(width: 900, height: 600),
        minimumSize: CGSize = CGSize(width: 480, height: 320),
        hasSettings: Bool = false
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.tint = tint
        self.category = category
        self.keywords = keywords
        self.defaultSize = defaultSize
        self.minimumSize = minimumSize
        self.hasSettings = hasSettings
        manifest = nil
    }

    public init(_ manifest: Manifest, language: Language) {
        id = manifest.id
        name = manifest.name.resolve(language)
        symbolName = manifest.symbol
        tint = manifest.tint
        category = manifest.category.resolve(language)
        keywords = []
        defaultSize = manifest.defaultSize
        minimumSize = manifest.minimumSize
        hasSettings = manifest.hasSettings
        self.manifest = manifest
    }

    /// Same app with name and category re-resolved; descriptors without a manifest are returned as is.
    public func localized(_ language: Language) -> AppDescriptor {
        manifest.map { AppDescriptor($0, language: language) } ?? self
    }
}
