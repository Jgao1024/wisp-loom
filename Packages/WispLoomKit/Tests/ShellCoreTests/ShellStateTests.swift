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

    @Test func activeAppFollowsKeyWindow() {
        let state = ShellState(apps: [])
        let other = WindowInstance(appID: "b")
        state.apply(.opened(first))
        state.apply(.opened(other))
        state.apply(.focused(other.id))
        #expect(state.activeAppID == "b")
        state.apply(.closed(other.id))
        #expect(state.activeAppID == "a")
    }
}
