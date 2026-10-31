/// A plain string or a language table. Fallback: current language → `en` → first key in sorted order
/// (JSON objects carry no order, so "first" has to be deterministic some other way).
public struct LocalizedText: Sendable, Hashable, Decodable, ExpressibleByStringLiteral {
    private let table: [String: String]

    public init(_ table: [String: String]) { self.table = table }
    public init(stringLiteral value: String) { table = ["en": value] }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            table = ["en": text]
        } else {
            table = try container.decode([String: String].self)
        }
    }

    public func resolve(_ language: Language) -> String {
        table[language.rawValue] ?? table["en"] ?? table.sorted { $0.key < $1.key }.first?.value ?? ""
    }
}
