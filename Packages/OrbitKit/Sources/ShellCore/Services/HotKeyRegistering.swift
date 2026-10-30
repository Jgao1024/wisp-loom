@MainActor
public protocol HotKeyRegistering: AnyObject {
    /// Returns false when the system refuses the combination; nothing stays registered then.
    func register(_ hotKey: HotKey, handler: @escaping @MainActor () -> Void) -> Bool
    func unregister()
}
