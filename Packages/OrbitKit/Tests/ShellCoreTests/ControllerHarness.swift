import Foundation

@testable import ShellCore

@MainActor
final class ControllerHarness {
    let notes = AppDescriptor(id: "test.notes", name: "Notes", symbolName: "note.text", tint: .yellow, category: "A")
    let windows = FakeWindowManager()
    let presenter = FakePresenter()
    let hotKeys = FakeHotKeys()
    let defaults: UserDefaults
    let state: ShellState
    let controller: ShellController

    init() {
        defaults = UserDefaults(suiteName: "orbit.tests." + UUID().uuidString)!
        state = ShellState(apps: [notes])
        controller = ShellController(
            state: state, windows: windows, presenter: presenter, hotKeys: hotKeys, defaults: defaults
        ) {}
    }
}
