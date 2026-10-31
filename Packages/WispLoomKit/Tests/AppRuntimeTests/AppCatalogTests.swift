import Foundation
import ShellCore
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

struct AppChangeTests {
    @Test func classifiesChangedFiles() throws {
        let box = try Sandbox()
        defer { box.remove() }
        let manifest = try Manifest.decode(Data(#"{"id":"x.one","name":"One","symbol":"star","ui":"ui.js"}"#.utf8))
        let directory = box.directory.appendingPathComponent("one")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bundles = [AppBundle(directory: directory, manifest: manifest)]
        let real = directory.resolvingSymlinksInPath().path

        #expect(AppCatalog.change(at: real + "/ui.js", in: bundles) == .script("x.one"))
        #expect(AppCatalog.change(at: real + "/backend/echo", in: bundles) == .backend("x.one"))
        #expect(AppCatalog.change(at: real + "/manifest.json", in: bundles) == .manifest)
        #expect(AppCatalog.change(at: real + "/notes.txt", in: bundles) == nil)
        #expect(AppCatalog.change(at: "/elsewhere/ui.js", in: bundles) == nil)
    }
}
