import Foundation

public struct WindowID: Hashable, Sendable {
    public let rawValue = UUID()

    public init() {}
}
