/// A key equivalent written by an app as `"cmd+shift+n"`.
public struct Shortcut: Sendable, Hashable {
    public let key: Character
    public let modifiers: HotKey.Modifiers

    public init?(_ text: String) {
        var modifiers: HotKey.Modifiers = []
        var key: Character?
        for part in text.lowercased().split(separator: "+") {
            switch part {
            case "cmd", "command": modifiers.insert(.command)
            case "shift": modifiers.insert(.shift)
            case "opt", "option", "alt": modifiers.insert(.option)
            case "ctrl", "control": modifiers.insert(.control)
            default:
                guard part.count == 1, key == nil else { return nil }
                key = part.first
            }
        }
        guard let key else { return nil }
        self.key = key
        self.modifiers = modifiers
    }
}
