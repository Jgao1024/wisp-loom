import Foundation
import Testing

@testable import ShellCore

struct StoredSettingTests {
    @Test func languageDefaultsToChinese() throws {
        let defaults = try #require(UserDefaults(suiteName: "orbit.tests." + UUID().uuidString))
        #expect(Language.stored(in: defaults) == .zhHans)
    }

    @Test func launcherStyleRoundTrip() throws {
        let defaults = try #require(UserDefaults(suiteName: "orbit.tests." + UUID().uuidString))
        LauncherStyle.grid.store(in: defaults)
        #expect(LauncherStyle.stored(in: defaults) == .grid)
    }
}
