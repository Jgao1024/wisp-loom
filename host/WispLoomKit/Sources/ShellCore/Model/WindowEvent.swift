public enum WindowEvent: Sendable, Hashable {
    case opened(WindowInstance)
    case closed(WindowID)
    case focused(WindowID)
}
