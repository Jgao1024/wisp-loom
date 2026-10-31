/// A menu-bar entry declared by the app with `<Command>`.
public struct AppCommand: Identifiable, Hashable {
    public let id: String
    public let menu: String
    public let title: String
    public let shortcut: Shortcut?
    public let isEnabled: Bool
    public let handler: String?
}

extension UITree {
    /// Reads node props, so calling this inside `withObservationTracking` re-runs when a command changes.
    public var commands: [AppCommand] {
        var result: [AppCommand] = []
        for node in nodes(ofType: "Command") {
            guard let menu = node.string("menu"), let title = node.string("title") else { continue }
            result.append(
                AppCommand(
                    id: node.id, menu: menu, title: title, shortcut: node.string("shortcut").flatMap(Shortcut.init),
                    isEnabled: !node.bool("disabled"), handler: node.handler("onAction")))
        }
        return result
    }

    public var hasSettings: Bool { !nodes(ofType: "Settings").isEmpty }
}
