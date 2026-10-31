import AppKit
import AppRuntime
import OSLog
import ShellCore
import ShellPlatform
import ShellUI
import SwiftUI

@MainActor
final class CompositionRoot {
    private let controller: ShellController
    private let registry: AppRegistry
    private let menus: MenuCoordinator
    private var hotReloader: HotReloader?
    private var statusItem: StatusItemController?

    init() {
        let logger = Logger(subsystem: "com.example.wisploom", category: "apps")
        let factory = WindowFactory()
        let state = ShellState(
            apps: [], launcherStyle: .stored(in: .standard), hotKey: .stored(in: .standard),
            language: .stored(in: .standard))
        let registry = AppRegistry(
            state: state, dataRoot: Self.supportDirectory.appendingPathComponent("Data"),
            log: { logger.info("\($0, privacy: .public)") })
        let windows = WindowManager(factory: factory)
        let presenter = ShellPresenter(factory: factory)
        let controller = ShellController(
            state: state, windows: windows, presenter: presenter, hotKeys: HotKeyCenter(),
            onQuit: { NSApp.terminate(nil) })
        let send: (ShellAction) -> Void = { [weak controller] in controller?.dispatch($0) }

        var hotReloader: HotReloader?
        windows.contentProvider = { registry.makeContent(for: $0, kind: $1) }
        windows.windowDidClose = { registry.windowClosed($0, content: $2) }
        registry.openSettings = { [weak controller] in controller?.dispatch(.openAppSettings($0)) }
        presenter.launcherContent = { NSHostingController(rootView: LauncherView(state: state, send: send)) }
        presenter.settingsPanes = {
            [
                SettingsPane(
                    id: "general", title: state.language.string("General"), symbol: "gearshape",
                    content: NSHostingController(rootView: SettingsView(state: state, send: send)))
            ]
        }
        controller.setApps(registry.load(from: Self.appRoots))
        if let override = ProcessInfo.processInfo.environment["WISP_APPS"] {
            hotReloader = HotReloader(root: URL(fileURLWithPath: override), registry: registry) { [weak controller] in
                controller?.setApps(registry.load(from: Self.appRoots))
            }
        }
        self.controller = controller
        self.registry = registry
        self.hotReloader = hotReloader
        menus = MenuCoordinator(state: state, registry: registry, send: send)
    }

    func start() {
        controller.start()
        menus.start()
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

    static var supportDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("WispLoom")
    }

    /// docs/01-architecture.md §6: bundled → Application Support → user-added directories.
    /// `WISP_APPS` replaces the whole list during development.
    static var appRoots: [URL] {
        if let override = ProcessInfo.processInfo.environment["WISP_APPS"] {
            return [URL(fileURLWithPath: override)]
        }
        var roots = [
            Bundle.main.resourceURL?.appendingPathComponent("Apps"), supportDirectory.appendingPathComponent("Apps"),
        ]
        let added = UserDefaults.standard.stringArray(forKey: "wisploom.appDirectories") ?? []
        roots += added.map { URL(fileURLWithPath: $0) }
        return roots.compactMap { $0 }
    }
}
