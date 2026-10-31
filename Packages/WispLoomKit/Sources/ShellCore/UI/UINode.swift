import Observation

/// One node per `@Observable` object: a patch only invalidates views that read what changed.
@MainActor
@Observable
public final class UINode: Identifiable {
    public nonisolated let id: String
    public internal(set) var type: String
    public internal(set) var props: [String: JSONValue]
    public internal(set) var children: [UINode] = []
    var parentID: String?

    init(id: String, type: String, props: [String: JSONValue]) {
        self.id = id
        self.type = type
        self.props = props
    }

    public func string(_ key: String) -> String? { props[key]?.stringValue }
    public func bool(_ key: String) -> Bool { props[key]?.boolValue ?? false }
    public func number(_ key: String) -> Double? { props[key]?.numberValue }
    /// Event props hold a handler id.
    public func handler(_ key: String) -> String? { props[key]?.stringValue }
}
