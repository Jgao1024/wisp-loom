import Foundation

public enum Language: String, CaseIterable, Identifiable, Sendable, StoredSetting {
    case zhHans = "zh-Hans"
    case en

    public var id: String { rawValue }
    public var name: String { self == .zhHans ? "中文" : "English" }
    public var locale: Locale { Locale(identifier: rawValue) }

    public static let storageKey = "orbit.language"
    public static let `default` = Language.zhHans

    /// For AppKit strings; SwiftUI text follows `locale` through the environment.
    public func string(_ key: String) -> String {
        let bundle = Bundle.main.path(forResource: rawValue, ofType: "lproj").flatMap(Bundle.init(path:))
        return bundle?.localizedString(forKey: key, value: nil, table: nil) ?? key
    }
}
