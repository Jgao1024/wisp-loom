import Foundation

public protocol StoredSetting: Codable {
    static var storageKey: String { get }
    static var `default`: Self { get }
}

extension StoredSetting {
    public static func stored(in defaults: UserDefaults) -> Self {
        defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? .default
    }

    public func store(in defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.storageKey)
    }
}
