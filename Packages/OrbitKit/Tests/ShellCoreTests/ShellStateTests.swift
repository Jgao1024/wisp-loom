import Testing

@testable import ShellCore

@MainActor
struct ShellStateTests {
    private let first = WindowInstance(appID: "a", isKey: true)
    private let second = WindowInstance(appID: "a")

    @Test func openedAddsWindowOnce() {
        let state = ShellState(apps: [])
        state.apply(.opened(first))
        state.apply(.opened(first))
        #expect(state.windows == [first])
    }

    @Test func focusedMovesKeyFlag() {
        let state = ShellState(apps: [])
        state.apply(.opened(first))
        state.apply(.opened(second))
        state.apply(.focused(second.id))
        #expect(state.window(for: "a")?.id == second.id)
    }

    @Test func closedRemovesWindow() {
        let state = ShellState(apps: [])
        state.apply(.opened(first))
        state.apply(.closed(first.id))
        #expect(state.window(for: "a") == nil)
    }
}
