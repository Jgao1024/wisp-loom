import CoreGraphics

public enum Spacing {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24

    /// The three steps an app may ask for on a `Stack`.
    static func stack(_ name: String?) -> CGFloat {
        switch name {
        case "tight": xs
        case "loose": l
        default: s
        }
    }
}
