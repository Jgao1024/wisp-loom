import Foundation
import Testing

@testable import AppRuntime

struct AppCatalogTests {
    private func app(_ root: URL, _ name: String, id: String, valid: Bool = true) throws {
        let directory = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = valid ? #"{"id":"\#(id)","name":"\#(name)","symbol":"star","ui":"ui.js"}"# : "{ nope"
        try json.write(to: directory.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
    }

    @Test func scansRootsInOrderAndSkipsBrokenOnes() throws {
        let box = try Sandbox()
        defer { box.remove() }
        let first = box.directory.appendingPathComponent("a")
        let second = box.directory.appendingPathComponent("b")
        try app(first, "one", id: "x.one")
        try app(first, "broken", id: "x.broken", valid: false)
        try app(second, "dup", id: "x.one")
        try app(second, "two", id: "x.two")

        let bundles = AppCatalog.scan([first, second, box.directory.appendingPathComponent("missing")])
        #expect(bundles.map(\.manifest.id.rawValue) == ["x.one", "x.two"])
        #expect(bundles[0].directory.lastPathComponent == "one")
    }
}
