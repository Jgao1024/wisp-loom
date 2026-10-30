import Foundation
import Testing

@testable import ShellCore

struct HotKeyTests {
    @Test func labelListsModifiersInSystemOrder() {
        let hotKey = HotKey(keyCode: 0, modifiers: [.command, .control, .shift, .option], key: "A")
        #expect(hotKey.label == "⌃⌥⇧⌘A")
    }

    @Test func storedFallsBackToDefault() throws {
        let defaults = try #require(UserDefaults(suiteName: "orbit.tests." + UUID().uuidString))
        #expect(HotKey.stored(in: defaults) == .default)
    }

    @Test func roundTrip() throws {
        let defaults = try #require(UserDefaults(suiteName: "orbit.tests." + UUID().uuidString))
        let hotKey = HotKey(keyCode: 40, modifiers: [.option, .command], key: "K")
        hotKey.store(in: defaults)
        #expect(HotKey.stored(in: defaults) == hotKey)
    }
}
