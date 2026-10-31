public enum UITreeError: Error, Equatable {
    case unknownNode(String)
    case duplicateNode(String)
    case indexOutOfRange(parent: String, index: Int)
    case cycle(String)
    case notAText(id: String, prop: String)
}

/// Node table for one app window. Patches apply atomically: ops run against a `Draft` overlay and
/// only a fully successful batch is written to the live nodes.
@MainActor
public final class UITree {
    public private(set) var root: UINode?
    public private(set) var rev = 0
    private var nodes: [String: UINode] = [:]

    public init() {}

    /// Returns false when the patch is stale (`rev` not newer) and was dropped. On error nothing changed;
    /// the caller should ask JS for a full `replace`.
    @discardableResult
    public func apply(_ patch: UIPatch) throws(UITreeError) -> Bool {
        guard patch.rev > rev else { return false }
        var draft = Draft(tree: self)
        for op in patch.ops { try draft.apply(op) }
        commit(draft)
        rev = patch.rev
        return true
    }

    /// Drops the whole table (window closed); `rev` stays so a later full replace is still accepted.
    public func reset() {
        root = nil
        nodes = [:]
    }

    public func node(_ id: String) -> UINode? { nodes[id] }

    /// Depth-first nodes of a type, e.g. every `Command` for the menu bar.
    public func nodes(ofType type: String, under start: UINode? = nil) -> [UINode] {
        var found: [UINode] = []
        var stack = [start ?? root].compactMap { $0 }
        while let node = stack.popLast() {
            if node.type == type { found.append(node) }
            stack.append(contentsOf: node.children.reversed())
        }
        return found
    }

    private func commit(_ draft: Draft) {
        var created: [UINode] = []
        for (id, entry) in draft.overrides {
            guard let entry else {
                nodes[id] = nil
                continue
            }
            if let node = nodes[id] {
                if node.type != entry.type { node.type = entry.type }
                if node.props != entry.props { node.props = entry.props }
            } else {
                let node = UINode(id: id, type: entry.type, props: entry.props)
                nodes[id] = node
                created.append(node)
            }
        }
        for (id, entry) in draft.overrides {
            guard let entry, let node = nodes[id] else { continue }
            node.parentID = entry.parent
            if node.children.map(\.id) != entry.children {
                var children: [UINode] = []
                for childID in entry.children {
                    if let child = nodes[childID] { children.append(child) }
                }
                node.children = children
            }
        }
        root = draft.rootID.flatMap { nodes[$0] }
    }

    fileprivate struct Entry {
        var type: String
        var props: [String: JSONValue]
        var children: [String]
        var parent: String?
    }

    /// Copy-on-write view over the live tree: cost is proportional to the ops, not the tree size.
    @MainActor fileprivate struct Draft {
        let tree: UITree
        var overrides: [String: Entry?] = [:]
        var rootID: String?

        init(tree: UITree) {
            self.tree = tree
            rootID = tree.root?.id
        }

        func entry(_ id: String) -> Entry? {
            if let overridden = overrides[id] { return overridden }
            guard let node = tree.nodes[id] else { return nil }
            return Entry(
                type: node.type, props: node.props, children: node.children.map(\.id), parent: node.parentID)
        }

        func require(_ id: String) throws(UITreeError) -> Entry {
            guard let entry = entry(id) else { throw .unknownNode(id) }
            return entry
        }

        mutating func apply(_ op: UIOp) throws(UITreeError) {
            switch op {
            case .replace(let node):
                try replace(node)
            case .insert(let parent, let index, let node):
                var entry = try require(parent)
                guard (0...entry.children.count).contains(index) else {
                    throw .indexOutOfRange(parent: parent, index: index)
                }
                try add(node, parent: parent)
                entry.children.insert(node.id, at: index)
                overrides[parent] = entry
            case .remove(let id):
                let entry = try require(id)
                try detach(id, from: entry.parent)
                drop(id)
            case .move(let id, let parent, let index):
                let entry = try require(id)
                var target = try require(parent)
                try checkNoCycle(moving: id, into: parent)
                try detach(id, from: entry.parent)
                target = try require(parent)
                guard (0...target.children.count).contains(index) else {
                    throw .indexOutOfRange(parent: parent, index: index)
                }
                target.children.insert(id, at: index)
                overrides[parent] = target
                var moved = try require(id)
                moved.parent = parent
                overrides[id] = moved
            case .update(let id, let props):
                var entry = try require(id)
                for (key, value) in props {
                    if value == .null { entry.props[key] = nil } else { entry.props[key] = value }
                }
                overrides[id] = entry
            case .append(let id, let prop, let value):
                var entry = try require(id)
                switch entry.props[prop] {
                case nil: entry.props[prop] = .string(value)
                case .string(let text)?: entry.props[prop] = .string(text + value)
                default: throw .notAText(id: id, prop: prop)
                }
                overrides[id] = entry
            }
        }

        /// Keeps the node's slot in its parent (same id); the old subtree is discarded.
        private mutating func replace(_ node: UINodeData) throws(UITreeError) {
            if let old = entry(node.id) {
                for child in old.children { drop(child) }
                overrides[node.id] = .some(nil)
                try add(node, parent: old.parent)
            } else if rootID == nil {
                try add(node, parent: nil)
                rootID = node.id
            } else {
                throw .unknownNode(node.id)
            }
        }

        private mutating func add(_ node: UINodeData, parent: String?) throws(UITreeError) {
            guard entry(node.id) == nil else { throw .duplicateNode(node.id) }
            overrides[node.id] = Entry(
                type: node.type, props: node.props, children: node.children.map(\.id), parent: parent)
            for child in node.children { try add(child, parent: node.id) }
        }

        private mutating func drop(_ id: String) {
            guard let entry = entry(id) else { return }
            overrides[id] = .some(nil)
            for child in entry.children { drop(child) }
            if rootID == id { rootID = nil }
        }

        private mutating func detach(_ id: String, from parent: String?) throws(UITreeError) {
            guard let parent else { return }
            var entry = try require(parent)
            entry.children.removeAll { $0 == id }
            overrides[parent] = entry
        }

        private func checkNoCycle(moving id: String, into parent: String) throws(UITreeError) {
            var cursor: String? = parent
            while let current = cursor {
                if current == id { throw .cycle(id) }
                cursor = entry(current)?.parent
            }
        }
    }
}
