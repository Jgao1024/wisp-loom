import AppKit
import ShellCore

public struct MenuCommand {
    public let menu: String
    public let title: String
    public let shortcut: Shortcut?
    public let isEnabled: Bool
    public let action: @MainActor () -> Void

    public init(
        menu: String, title: String, shortcut: Shortcut?, isEnabled: Bool, action: @escaping @MainActor () -> Void
    ) {
        self.menu = menu
        self.title = title
        self.shortcut = shortcut
        self.isEnabled = isEnabled
        self.action = action
    }
}

/// What the menu bar shows for the current key window's app (docs/03-native-ui.md §2).
public struct MenuModel {
    public var appName: String
    public var commands: [MenuCommand]
    public var openSettings: (@MainActor () -> Void)?
    public var toggleSidebar: (@MainActor () -> Void)?
    public var quit: @MainActor () -> Void
    public var language: Language

    public init(
        appName: String, commands: [MenuCommand], openSettings: (@MainActor () -> Void)?,
        toggleSidebar: (@MainActor () -> Void)? = nil, quit: @escaping @MainActor () -> Void, language: Language
    ) {
        self.appName = appName
        self.commands = commands
        self.openSettings = openSettings
        self.toggleSidebar = toggleSidebar
        self.quit = quit
        self.language = language
    }
}

/// Rebuilds `NSApp.mainMenu` from a model. Standard items use responder-chain selectors, so they act on
/// whatever is focused. Also kept while the app is `.accessory`, so ⌘C / ⌘V work in the launcher.
@MainActor
public final class MenuBarController: NSObject {
    private var actions: [@MainActor () -> Void] = []

    public override init() { super.init() }

    public func rebuild(_ model: MenuModel) {
        actions = []
        let t = model.language.string
        let main = NSMenu()

        let appMenu = NSMenu()
        item(appMenu, "\(t("About")) \(model.appName)", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        if let openSettings = model.openSettings {
            appMenu.addItem(.separator())
            custom(appMenu, t("Settings…"), shortcut: Shortcut("cmd+,"), enabled: true, action: openSettings)
        }
        appMenu.addItem(.separator())
        let services = NSMenu(title: t("Services"))
        NSApp.servicesMenu = services
        appMenu.addItem(withTitle: t("Services"), action: nil, keyEquivalent: "").submenu = services
        appMenu.addItem(.separator())
        item(appMenu, "\(t("Hide")) \(model.appName)", #selector(NSApplication.hide(_:)), "h")
        item(appMenu, t("Hide Others"), #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        item(appMenu, t("Show All"), #selector(NSApplication.unhideAllApplications(_:)))
        appMenu.addItem(.separator())
        custom(appMenu, "\(t("Quit")) \(model.appName)", shortcut: Shortcut("cmd+q"), enabled: true, action: model.quit)
        add(appMenu, to: main, title: model.appName)

        let file = NSMenu(title: t("File"))
        commands(model, "file", into: file)
        if file.items.isEmpty == false { file.addItem(.separator()) }
        item(file, t("Close Window"), #selector(NSWindow.performClose(_:)), "w")
        add(file, to: main, title: t("File"))

        let edit = NSMenu(title: t("Edit"))
        item(edit, t("Undo"), NSSelectorFromString("undo:"), "z")
        item(edit, t("Redo"), NSSelectorFromString("redo:"), "z", [.command, .shift])
        edit.addItem(.separator())
        item(edit, t("Cut"), #selector(NSText.cut(_:)), "x")
        item(edit, t("Copy"), #selector(NSText.copy(_:)), "c")
        item(edit, t("Paste"), #selector(NSText.paste(_:)), "v")
        item(edit, t("Select All"), #selector(NSText.selectAll(_:)), "a")
        edit.addItem(.separator())
        let find = item(edit, t("Find…"), #selector(NSResponder.performTextFinderAction(_:)), "f")
        find.tag = NSTextFinder.Action.showFindInterface.rawValue
        add(edit, to: main, title: t("Edit"))

        let view = NSMenu(title: t("View"))
        if let toggleSidebar = model.toggleSidebar {
            // The page's sidebar is a Web column; the host hands ⌃⌘S to the same toggle its toolbar item uses.
            custom(view, t("Toggle Sidebar"), shortcut: Shortcut("cmd+ctrl+s"), enabled: true, action: toggleSidebar)
        } else {
            item(
                view, t("Toggle Sidebar"), #selector(NSSplitViewController.toggleSidebar(_:)), "s",
                [.command, .control])
        }
        commands(model, "view", into: view)
        view.addItem(.separator())
        item(view, t("Enter Full Screen"), #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])
        add(view, to: main, title: t("View"))

        let window = NSMenu(title: t("Window"))
        item(window, t("Minimize"), #selector(NSWindow.performMiniaturize(_:)), "m")
        item(window, t("Zoom"), #selector(NSWindow.performZoom(_:)))
        NSApp.windowsMenu = window
        add(window, to: main, title: t("Window"))

        let help = NSMenu(title: t("Help"))
        NSApp.helpMenu = help
        add(help, to: main, title: t("Help"))

        NSApp.mainMenu = main
    }

    @objc private func run(_ sender: NSMenuItem) { actions[sender.tag]() }

    private func commands(_ model: MenuModel, _ menu: String, into target: NSMenu) {
        for command in model.commands where command.menu == menu {
            custom(
                target, command.title, shortcut: command.shortcut, enabled: command.isEnabled, action: command.action)
        }
    }

    private func custom(
        _ menu: NSMenu, _ title: String, shortcut: Shortcut?, enabled: Bool, action: @escaping @MainActor () -> Void
    ) {
        let entry = NSMenuItem(
            title: title, action: #selector(run(_:)), keyEquivalent: shortcut.map { String($0.key) } ?? "")
        entry.target = self
        entry.tag = actions.count
        entry.isEnabled = enabled
        if let shortcut { entry.keyEquivalentModifierMask = shortcut.modifiers.eventFlags }
        actions.append(action)
        menu.addItem(entry)
    }

    @discardableResult
    private func item(
        _ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "",
        _ modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let entry = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        if !key.isEmpty { entry.keyEquivalentModifierMask = modifiers }
        return entry
    }

    private func add(_ submenu: NSMenu, to main: NSMenu, title: String) {
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = submenu
        main.addItem(holder)
    }
}

extension HotKey.Modifiers {
    fileprivate var eventFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.command) { flags.insert(.command) }
        if contains(.shift) { flags.insert(.shift) }
        if contains(.option) { flags.insert(.option) }
        if contains(.control) { flags.insert(.control) }
        return flags
    }
}
