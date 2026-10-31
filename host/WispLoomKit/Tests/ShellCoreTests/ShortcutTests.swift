import Testing

@testable import ShellCore

struct ShortcutTests {
    @Test func parsesModifiersAndKey() {
        let shortcut = Shortcut("cmd+Shift+N")
        #expect(shortcut?.key == "n")
        #expect(shortcut?.modifiers == [.command, .shift])
    }

    @Test func rejectsMissingOrExtraKeys() {
        #expect(Shortcut("cmd") == nil)
        #expect(Shortcut("cmd+a+b") == nil)
        #expect(Shortcut("") == nil)
    }
}
