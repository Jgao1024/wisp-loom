import Foundation
import Testing

@testable import ShellCore

@MainActor
struct ShellControllerTests {
    @Test func openAppOpensWindowAndHidesLauncher() {
        let h = ControllerHarness()
        h.presenter.isLauncherVisible = true
        h.controller.dispatch(.openApp(h.notes.id))
        #expect(h.windows.opened == [h.notes.id])
        #expect(!h.presenter.isLauncherVisible)
    }

    @Test func openAppFocusesExistingWindow() {
        let h = ControllerHarness()
        let window = WindowInstance(appID: h.notes.id)
        h.state.apply(.opened(window))
        h.controller.dispatch(.openApp(h.notes.id))
        #expect(h.windows.focused == [window.id])
        #expect(h.windows.opened.isEmpty)
    }

    @Test func openUnknownAppDoesNothing() {
        let h = ControllerHarness()
        h.controller.dispatch(.openApp("test.unknown"))
        #expect(h.windows.opened.isEmpty)
    }

    @Test func toggleLauncherFlipsVisibility() {
        let h = ControllerHarness()
        h.controller.dispatch(.toggleLauncher)
        #expect(h.presenter.isLauncherVisible)
        h.controller.dispatch(.toggleLauncher)
        #expect(!h.presenter.isLauncherVisible)
    }

    @Test func openSettingsHidesLauncherAndShowsSettings() {
        let h = ControllerHarness()
        h.controller.dispatch(.showLauncher)
        h.controller.dispatch(.openSettings)
        #expect(!h.presenter.isLauncherVisible)
        #expect(h.presenter.settingsShown == 1)
    }

    @Test func launcherStyleIsPersisted() {
        let h = ControllerHarness()
        h.controller.dispatch(.setLauncherStyle(.grid))
        #expect(h.state.launcherStyle == .grid)
        #expect(LauncherStyle.stored(in: h.defaults) == .grid)
    }

    @Test func setHotKeyRegistersAndPersists() {
        let h = ControllerHarness()
        let hotKey = HotKey(keyCode: 0, modifiers: [.command, .shift], key: "A")
        h.controller.dispatch(.setHotKey(hotKey))
        #expect(h.state.hotKey == hotKey)
        #expect(h.hotKeys.registered == hotKey)
        #expect(HotKey.stored(in: h.defaults) == hotKey)
    }

    @Test func rejectedHotKeyKeepsPreviousOne() {
        let h = ControllerHarness()
        h.controller.start()
        defer { h.controller.stop() }
        h.hotKeys.rejects = true
        h.controller.dispatch(.setHotKey(HotKey(keyCode: 0, modifiers: .command, key: "A")))
        h.hotKeys.rejects = false
        #expect(h.state.hotKey == .default)
        #expect(HotKey.stored(in: h.defaults) == .default)
    }

    @Test func startRegistersStoredHotKey() {
        let h = ControllerHarness()
        h.controller.start()
        defer { h.controller.stop() }
        #expect(h.hotKeys.registered == .default)
    }

    @Test func setLanguageUpdatesStateAndPersists() {
        let h = ControllerHarness()
        #expect(h.state.language == .zhHans)
        h.controller.dispatch(.setLanguage(.en))
        #expect(h.state.language == .en)
        #expect(Language.stored(in: h.defaults) == .en)
    }

    @Test func stopClosesAllWindows() {
        let h = ControllerHarness()
        h.controller.stop()
        #expect(h.windows.didCloseAll)
    }

    @Test func startConsumesWindowEvents() async throws {
        let h = ControllerHarness()
        h.controller.start()
        defer { h.controller.stop() }
        let window = WindowInstance(appID: h.notes.id)
        h.windows.send(.opened(window))
        for _ in 0..<200 where h.state.windows.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        #expect(h.state.windows == [window])
    }

    @Test func openAppSettingsOpensOnceThenFocuses() {
        let h = ControllerHarness()
        h.controller.dispatch(.openAppSettings(h.notes.id))
        #expect(h.windows.settingsOpened == [h.notes.id])
        // A main window alone must not count as the settings window.
        h.state.apply(.opened(WindowInstance(appID: h.notes.id)))
        h.controller.dispatch(.openAppSettings(h.notes.id))
        #expect(h.windows.settingsOpened.count == 2)
        let settings = WindowInstance(appID: h.notes.id, kind: .settings)
        h.state.apply(.opened(settings))
        h.controller.dispatch(.openAppSettings(h.notes.id))
        #expect(h.windows.focused == [settings.id])
    }

    @Test func closeAppClosesOnlyThatApp() {
        let h = ControllerHarness()
        h.controller.dispatch(.closeApp(h.notes.id))
        #expect(h.windows.closedApps == [h.notes.id])
    }

    @Test func appWithoutSettingsIgnoresOpenAppSettings() {
        let h = ControllerHarness()
        let plain = AppDescriptor(id: "test.plain", name: "Plain", symbolName: "star", tint: .blue, category: "A")
        h.controller.setApps([h.notes, plain])
        h.controller.dispatch(.openAppSettings(plain.id))
        #expect(h.windows.settingsOpened.isEmpty)
    }
}
