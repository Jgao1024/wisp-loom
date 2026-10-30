import AppKit
import ShellCore
import ShellPlatform
import ShellUI
import SwiftUI

@MainActor
final class CompositionRoot {
    private let controller: ShellController
    private var statusItem: StatusItemController?

    init() {
        let factory = WindowFactory()
        let state = ShellState(
            apps: AppDescriptor.samples, launcherStyle: .stored(in: .standard),
            hotKey: .stored(in: .standard), language: .stored(in: .standard))
        let windows = WindowManager(factory: factory)
        let presenter = ShellPresenter(factory: factory)
        let controller = ShellController(
            state: state, windows: windows, presenter: presenter, hotKeys: HotKeyCenter(),
            onQuit: { NSApp.terminate(nil) })
        let send: (ShellAction) -> Void = { [weak controller] in controller?.dispatch($0) }

        windows.contentProvider = { NSHostingController(rootView: AppWindowView(app: $0)) }
        presenter.launcherContent = { NSHostingController(rootView: LauncherView(state: state, send: send)) }
        presenter.settingsContent = { NSHostingController(rootView: SettingsView(state: state, send: send)) }
        self.controller = controller
    }

    func start() {
        controller.start()
        statusItem = StatusItemController(
            symbolName: "circle.hexagongrid.fill",
            onClick: { [controller] in controller.dispatch(.toggleLauncher) },
            entries: { [controller] in
                [
                    .init(controller.state.language.string("Settings…")) { controller.dispatch(.openSettings) },
                    .init(controller.state.language.string("Quit")) { controller.dispatch(.quit) },
                ]
            })
        controller.dispatch(.showLauncher)
    }

    func stop() { controller.stop() }
}
