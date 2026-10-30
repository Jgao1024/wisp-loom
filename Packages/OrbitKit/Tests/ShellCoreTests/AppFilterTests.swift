import Testing

@testable import ShellCore

struct AppFilterTests {
    private let apps = [
        AppDescriptor(id: "a", name: "Notes", symbolName: "", tint: .blue, category: "Work"),
        AppDescriptor(id: "b", name: "Terminal", symbolName: "", tint: .gray, category: "Dev", keywords: ["shell"]),
    ]

    @Test func blankQueryKeepsOrder() { #expect(apps.matching("  ").map(\.id.rawValue) == ["a", "b"]) }
    @Test func categoryFilters() { #expect(apps.matching("", category: "Dev").map(\.id.rawValue) == ["b"]) }
    @Test func keywordsMatch() { #expect(apps.matching("shell").map(\.id.rawValue) == ["b"]) }
    @Test func noMatchIsEmpty() { #expect(apps.matching("zzz").isEmpty) }
}
