import Testing

@testable import ShellCore

struct FuzzyMatcherTests {
    @Test func emptyQueryMatchesEverything() {
        #expect(FuzzyMatcher.score("", in: "Notes") == 0)
        #expect(FuzzyMatcher.score("   ", in: "Notes") == 0)
    }

    @Test func exactMatchOutranksPrefix() {
        let exact = FuzzyMatcher.score("notes", in: "Notes")
        let prefix = FuzzyMatcher.score("note", in: "Notes")
        #expect(exact == 1000)
        #expect(prefix != nil)
        #expect(exact! > prefix!)
    }

    @Test func prefixMatch() {
        #expect(FuzzyMatcher.score("no", in: "Notes") != nil)
        #expect(FuzzyMatcher.score("No", in: "Notes") != nil)
    }

    @Test func containsMatch() {
        #expect(FuzzyMatcher.score("ote", in: "Notes") != nil)
        #expect(FuzzyMatcher.score("ote", in: "Notes")! < FuzzyMatcher.score("no", in: "Notes")!)
    }

    @Test func initialsMatch() {
        #expect(FuzzyMatcher.score("ss", in: "System Settings") != nil)
        #expect(FuzzyMatcher.score("zz", in: "System Settings") == nil)
    }

    @Test func caseInsensitive() {
        #expect(FuzzyMatcher.score("NOTES", in: "notes") == 1000)
        #expect(FuzzyMatcher.score("nOtEs", in: "NOTES") == 1000)
    }

    @Test func chineseCharacters() {
        #expect(FuzzyMatcher.score("笔记", in: "笔记") == 1000)
        #expect(FuzzyMatcher.score("笔", in: "笔记") != nil)
        #expect(FuzzyMatcher.score("记", in: "笔记") != nil)
        #expect(FuzzyMatcher.score("系统", in: "系统设置") != nil)
        #expect(FuzzyMatcher.score("设置", in: "系统设置") != nil)
    }

    @Test func subsequenceMatch() {
        #expect(FuzzyMatcher.score("nts", in: "Notes") != nil)
        #expect(FuzzyMatcher.score("nts", in: "Notes")! < FuzzyMatcher.score("note", in: "Notes")!)
    }

    @Test func unmatchedQueryReturnsNil() {
        #expect(FuzzyMatcher.score("xyz", in: "Notes") == nil)
        #expect(FuzzyMatcher.score("笔记", in: "Files") == nil)
    }

    @Test func candidatesUseBestScore() {
        #expect(FuzzyMatcher.score("finder", in: ["Files", "Finder", "folder"]) == 1000)
        #expect(FuzzyMatcher.score("xyz", in: ["Files", "Finder"]) == nil)
    }
}
