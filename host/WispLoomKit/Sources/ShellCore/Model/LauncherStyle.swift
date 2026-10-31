public enum LauncherStyle: String, CaseIterable, Identifiable, Sendable, StoredSetting {
    case grid

    public var id: String { rawValue }

    public static let storageKey = "wisploom.launcherStyle"
    public static let `default` = LauncherStyle.grid
}
