import CoreGraphics
import Testing

@testable import ShellCore

struct ManifestTests {
    @Test func decodesAllFields() throws {
        let manifest = try Fixtures.manifest()
        #expect(manifest.id == "dev.wisp.sample")
        #expect(manifest.tint == .purple)
        #expect(manifest.backend?.exec == ["backend/echo"])
        #expect(manifest.backend?.idle == 30)
        #expect(manifest.defaultSize == CGSize(width: 1100, height: 720))
        #expect(manifest.minimumSize == CGSize(width: 720, height: 480))
    }

    @Test func currentLanguageWins() throws {
        let manifest = try Fixtures.manifest()
        #expect(manifest.name.resolve(.zhHans) == "示例")
        #expect(manifest.name.resolve(.en) == "Sample")
    }

    @Test func fallsBackToEnglishThenFirst() throws {
        let manifest = try Fixtures.manifest()
        let english = LocalizedText(["en": "A", "ja": "B"])
        #expect(english.resolve(.zhHans) == "A")
        #expect(manifest.category.resolve(.en) == "Outils")  // no en: first by key order
    }

    @Test func plainStringIsEveryLanguage() throws {
        let json = Fixtures.manifestJSON.replacingOccurrences(
            of: #"{ "zh-Hans": "示例", "en": "Sample" }"#, with: #""Plain""#)
        let manifest = try Fixtures.manifest(json)
        #expect(manifest.name.resolve(.zhHans) == "Plain")
    }

    @Test func defaultsApplyWhenOptional() throws {
        let manifest = try Fixtures.manifest(
            #"{"id":"a","name":"A","symbol":"star","ui":"ui.js"}"#)
        #expect(manifest.backend == nil)
        #expect(manifest.tint == .accent)
        #expect(manifest.defaultSize == CGSize(width: 900, height: 600))
    }

    @Test func missingRequiredFieldThrows() {
        #expect(throws: (any Error).self) { try Fixtures.manifest(#"{"id":"a","name":"A"}"#) }
    }

    @Test func descriptorFollowsLanguage() throws {
        let app = AppDescriptor(try Fixtures.manifest(), language: .zhHans)
        #expect(app.name == "示例")
        #expect(app.localized(.en).name == "Sample")
        #expect(app.symbolName == "sparkles")
    }
}
