import CoreGraphics
import Foundation

/// `manifest.json` in an app directory; see docs/02-app-protocol.md §1.
public struct Manifest: Sendable, Hashable, Decodable {
    public struct Backend: Sendable, Hashable, Decodable {
        /// Command relative to the app directory, e.g. `["backend/agent"]`.
        public let exec: [String]
        /// Seconds without requests before the backend is closed; 0 keeps it running.
        public let idle: Int
    }

    public let id: AppID
    public let name: LocalizedText
    public let category: LocalizedText
    public let symbol: String
    public let tint: AppTint
    public let ui: String
    public let backend: Backend?
    /// The app has a settings window (menu item ⌘,).
    public let hasSettings: Bool
    public let defaultSize: CGSize
    public let minimumSize: CGSize

    private enum CodingKeys: String, CodingKey { case id, name, category, symbol, tint, ui, backend, settings, window }
    private struct Window: Decodable { let size: [Double]?, min: [Double]? }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(AppID.self, forKey: .id)
        guard !id.rawValue.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "empty id")
        }
        name = try c.decode(LocalizedText.self, forKey: .name)
        category = try c.decodeIfPresent(LocalizedText.self, forKey: .category) ?? LocalizedText([:])
        symbol = try c.decode(String.self, forKey: .symbol)
        tint = try c.decodeIfPresent(AppTint.self, forKey: .tint) ?? .accent
        ui = try c.decode(String.self, forKey: .ui)
        backend = try c.decodeIfPresent(Backend.self, forKey: .backend)
        hasSettings = try c.decodeIfPresent(Bool.self, forKey: .settings) ?? false
        let window = try c.decodeIfPresent(Window.self, forKey: .window)
        defaultSize = Self.size(window?.size) ?? CGSize(width: 900, height: 600)
        minimumSize = Self.size(window?.min) ?? CGSize(width: 480, height: 320)
    }

    public static func decode(_ data: Data) throws -> Manifest {
        try JSONDecoder().decode(Manifest.self, from: data)
    }

    private static func size(_ pair: [Double]?) -> CGSize? {
        guard let pair, pair.count == 2 else { return nil }
        return CGSize(width: pair[0], height: pair[1])
    }
}
