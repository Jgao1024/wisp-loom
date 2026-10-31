/// Wire form of a node. Event props carry handler ids; the functions stay in JS.
public struct UINodeData: Sendable, Hashable, Decodable {
    public let id: String
    public let type: String
    public let props: [String: JSONValue]
    public let children: [UINodeData]

    public init(id: String, type: String, props: [String: JSONValue] = [:], children: [UINodeData] = []) {
        self.id = id
        self.type = type
        self.props = props
        self.children = children
    }

    private enum CodingKeys: String, CodingKey { case id, type, props, children }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        props = try container.decodeIfPresent([String: JSONValue].self, forKey: .props) ?? [:]
        children = try container.decodeIfPresent([UINodeData].self, forKey: .children) ?? []
    }
}

public enum UIOp: Sendable, Hashable, Decodable {
    /// Replaces the subtree with the same id in place; on an empty tree it becomes the root.
    case replace(UINodeData)
    case insert(parent: String, index: Int, node: UINodeData)
    case remove(id: String)
    /// `index` counts positions after the node left its old parent.
    case move(id: String, parent: String, index: Int)
    /// Merges props; a `null` value deletes the key.
    case update(id: String, props: [String: JSONValue])
    case append(id: String, prop: String, value: String)

    private enum CodingKeys: String, CodingKey { case op, id, parent, index, node, props, prop, value }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .op) {
        case "replace":
            self = .replace(try c.decode(UINodeData.self, forKey: .node))
        case "insert":
            self = .insert(
                parent: try c.decode(String.self, forKey: .parent), index: try c.decode(Int.self, forKey: .index),
                node: try c.decode(UINodeData.self, forKey: .node))
        case "remove":
            self = .remove(id: try c.decode(String.self, forKey: .id))
        case "move":
            self = .move(
                id: try c.decode(String.self, forKey: .id), parent: try c.decode(String.self, forKey: .parent),
                index: try c.decode(Int.self, forKey: .index))
        case "update":
            self = .update(
                id: try c.decode(String.self, forKey: .id),
                props: try c.decode([String: JSONValue].self, forKey: .props))
        case "append":
            self = .append(
                id: try c.decode(String.self, forKey: .id), prop: try c.decode(String.self, forKey: .prop),
                value: try c.decode(String.self, forKey: .value))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .op, in: c, debugDescription: "unknown op \(other)")
        }
    }
}

public struct UIPatch: Sendable, Hashable, Decodable {
    public let rev: Int
    public let ops: [UIOp]

    public init(rev: Int, ops: [UIOp]) {
        self.rev = rev
        self.ops = ops
    }
}
