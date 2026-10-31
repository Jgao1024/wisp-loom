import AppKit
import AppRuntime
import Observation
import ShellCore
import ShellPlatform

/// Keeps the menu bar in step with the key window's app. Rebuilds when the active app or language change
/// (observed) and when an app registers new commands (pushed by the registry).
@MainActor
final class MenuCoordinator {
    private let menu = MenuBarController()
    private let state: ShellState
    private let registry: AppRegistry
    private let send: (ShellAction) -> Void

    init(state: ShellState, registry: AppRegistry, send: @escaping (ShellAction) -> Void) {
        self.state = state
        self.registry = registry
        self.send = send
        registry.onCommandsChange = { [weak self] in self?.refresh() }
    }

    func start() { refresh() }

    private func refresh() {
        let model = withObservationTracking {
            model()
        } onChange: { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        menu.rebuild(model)
    }

    private func model() -> MenuModel {
        let language = state.language
        guard let id = state.activeAppID, let app = state.app(for: id) else {
            return MenuModel(
                appName: "Wisp Loom", commands: [], openSettings: { [send] in send(.openSettings) },
                quit: { [send] in send(.quit) }, language: language)
        }
        var commands: [MenuCommand] = []
        for command in registry.commands(for: id) {
            let commandID = command.id
            commands.append(
                MenuCommand(
                    menu: command.menu, title: command.title, shortcut: command.shortcut, isEnabled: command.isEnabled,
                    action: { [registry] in registry.fire(commandID, in: id) }))
        }
        var openSettings: (@MainActor () -> Void)?
        if app.hasSettings { openSettings = { [send] in send(.openAppSettings(id)) } }
        let quit: @MainActor () -> Void = { [send] in send(.closeApp(id)) }
        return MenuModel(
            appName: app.name, commands: commands, openSettings: openSettings, quit: quit, language: language)
    }
}
