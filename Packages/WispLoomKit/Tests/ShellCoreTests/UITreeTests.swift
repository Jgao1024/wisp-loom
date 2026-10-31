import Testing

@testable import ShellCore

@MainActor
struct UITreeTests {
    private func tree(_ json: String? = nil) throws -> UITree {
        let tree = UITree()
        let seed =
            json
                ?? """
                {"rev":1,"ops":[{"op":"replace","node":{"id":"r","type":"Stack","props":{},"children":[
                  {"id":"a","type":"Text","props":{"text":"A"},"children":[]},
                  {"id":"b","type":"Text","props":{"text":"B"},"children":[]}]}}]}
                """
        try tree.apply(Fixtures.patch(seed))
        return tree
    }

    private func ids(_ tree: UITree, _ parent: String = "r") -> [String] {
        tree.node(parent)?.children.map(\.id) ?? []
    }

    @Test func replaceBuildsRoot() throws {
        let tree = try tree()
        #expect(tree.root?.id == "r")
        #expect(ids(tree) == ["a", "b"])
        #expect(tree.node("a")?.string("text") == "A")
    }

    @Test func replaceSwapsSubtreeInPlace() throws {
        let tree = try tree()
        try tree.apply(
            Fixtures.patch(
                #"{"rev":2,"ops":[{"op":"replace","node":{"id":"a","type":"Button","props":{},"children":[{"id":"c","type":"Text"}]}}]}"#
            ))
        #expect(ids(tree) == ["a", "b"])
        #expect(tree.node("a")?.type == "Button")
        #expect(ids(tree, "a") == ["c"])
    }

    @Test func insertAtIndex() throws {
        let tree = try tree()
        try tree.apply(
            Fixtures.patch(
                #"{"rev":2,"ops":[{"op":"insert","parent":"r","index":1,"node":{"id":"x","type":"Text","props":{}}}]}"#)
        )
        #expect(ids(tree) == ["a", "x", "b"])
    }

    @Test func removeDropsSubtree() throws {
        let tree = try tree()
        try tree.apply(Fixtures.patch(#"{"rev":2,"ops":[{"op":"remove","id":"a"}]}"#))
        #expect(ids(tree) == ["b"])
        #expect(tree.node("a") == nil)
    }

    @Test func moveReorders() throws {
        let tree = try tree()
        try tree.apply(Fixtures.patch(#"{"rev":2,"ops":[{"op":"move","id":"b","parent":"r","index":0}]}"#))
        #expect(ids(tree) == ["b", "a"])
    }

    @Test func moveIntoOtherParent() throws {
        let tree = try tree()
        try tree.apply(Fixtures.patch(#"{"rev":2,"ops":[{"op":"move","id":"b","parent":"a","index":0}]}"#))
        #expect(ids(tree) == ["a"])
        #expect(ids(tree, "a") == ["b"])
    }

    @Test func updateMergesAndNullDeletes() throws {
        let tree = try tree()
        try tree.apply(
            Fixtures.patch(#"{"rev":2,"ops":[{"op":"update","id":"a","props":{"text":null,"style":"title"}}]}"#))
        #expect(tree.node("a")?.string("text") == nil)
        #expect(tree.node("a")?.string("style") == "title")
    }

    @Test func appendConcatenates() throws {
        let tree = try tree()
        try tree.apply(
            Fixtures.patch(
                #"{"rev":2,"ops":[{"op":"append","id":"a","prop":"text","value":"1"},{"op":"append","id":"a","prop":"text","value":"2"}]}"#
            ))
        #expect(tree.node("a")?.string("text") == "A12")
    }

    @Test func staleRevIsDropped() throws {
        let tree = try tree()
        let applied = try tree.apply(Fixtures.patch(#"{"rev":1,"ops":[{"op":"remove","id":"a"}]}"#))
        #expect(!applied)
        #expect(ids(tree) == ["a", "b"])
        #expect(tree.rev == 1)
    }

    @Test func failedBatchRollsBack() throws {
        let tree = try tree()
        let patch = try Fixtures.patch(
            #"{"rev":2,"ops":[{"op":"remove","id":"a"},{"op":"update","id":"b","props":{"text":"changed"}},{"op":"remove","id":"missing"}]}"#
        )
        #expect(throws: UITreeError.unknownNode("missing")) { try tree.apply(patch) }
        #expect(ids(tree) == ["a", "b"])
        #expect(tree.node("b")?.string("text") == "B")
        #expect(tree.rev == 1)
        // A full replace with the same rev number as the failed batch still goes through.
        try tree.apply(
            Fixtures.patch(
                #"{"rev":2,"ops":[{"op":"replace","node":{"id":"r","type":"Stack","props":{},"children":[]}}]}"#))
        #expect(ids(tree).isEmpty)
    }

    @Test func rejectsBadIndexDuplicateAndCycle() throws {
        let tree = try tree()
        let badIndex = try Fixtures.patch(
            #"{"rev":2,"ops":[{"op":"insert","parent":"r","index":5,"node":{"id":"x","type":"Text"}}]}"#)
        #expect(throws: UITreeError.indexOutOfRange(parent: "r", index: 5)) { try tree.apply(badIndex) }
        let duplicate = try Fixtures.patch(
            #"{"rev":2,"ops":[{"op":"insert","parent":"r","index":0,"node":{"id":"a","type":"Text"}}]}"#)
        #expect(throws: UITreeError.duplicateNode("a")) { try tree.apply(duplicate) }
        let cycle = try Fixtures.patch(#"{"rev":2,"ops":[{"op":"move","id":"r","parent":"a","index":0}]}"#)
        #expect(throws: UITreeError.cycle("r")) { try tree.apply(cycle) }
    }

    @Test func appendToNonTextFails() throws {
        let tree = try tree(
            #"{"rev":1,"ops":[{"op":"replace","node":{"id":"r","type":"Stack","props":{"n":1}}}]}"#)
        let patch = try Fixtures.patch(#"{"rev":2,"ops":[{"op":"append","id":"r","prop":"n","value":"x"}]}"#)
        #expect(throws: UITreeError.notAText(id: "r", prop: "n")) { try tree.apply(patch) }
    }

    @Test func nodeIdentitySurvivesUpdate() throws {
        let tree = try tree()
        let before = tree.node("a")
        try tree.apply(Fixtures.patch(#"{"rev":2,"ops":[{"op":"update","id":"a","props":{"text":"Z"}}]}"#))
        #expect(tree.node("a") === before)
    }

    @Test func resetClearsNodesButKeepsRev() throws {
        let tree = try tree()
        tree.reset()
        #expect(tree.root == nil && tree.node("a") == nil)
        #expect(tree.rev == 1)
    }

    @Test func findsNodesByType() throws {
        let tree = try tree()
        #expect(tree.nodes(ofType: "Text").map(\.id) == ["a", "b"])
    }
}
