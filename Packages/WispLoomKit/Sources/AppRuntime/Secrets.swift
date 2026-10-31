import Foundation
import Security
import ShellCore

public protocol SecretStore: Sendable {
    func get(app: AppID, key: String) -> String?
    func set(app: AppID, key: String, value: String) throws
    func delete(app: AppID, key: String) throws
}

/// Generic-password items, one service per app so apps cannot see each other's keys.
public struct KeychainSecretStore: SecretStore {
    public struct Failure: Error { public let status: OSStatus }

    private let service: String

    public init(service: String = "com.example.wisploom") { self.service = service }

    public func get(app: AppID, key: String) -> String? {
        var query = identity(app, key)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    public func set(app: AppID, key: String, value: String) throws {
        let data = Data(value.utf8)
        let status = SecItemUpdate(identity(app, key) as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = identity(app, key)
            item[kSecValueData] = data
            let added = SecItemAdd(item as CFDictionary, nil)
            if added != errSecSuccess { throw Failure(status: added) }
        } else if status != errSecSuccess {
            throw Failure(status: status)
        }
    }

    public func delete(app: AppID, key: String) throws {
        let status = SecItemDelete(identity(app, key) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound { throw Failure(status: status) }
    }

    private func identity(_ app: AppID, _ key: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: "\(service).\(app.rawValue)", kSecAttrAccount: key]
    }
}

/// `shell.*` methods, callable by the backend and (restricted) by the UI. Add a method only when an app needs it.
struct ShellCapabilities: Sendable {
    enum Caller { case ui, backend }

    let appID: AppID
    let secrets: any SecretStore

    func handle(_ method: String, params: Data, from caller: Caller) -> Result<Data, CallFailure> {
        let object = (try? JSONDecoder().decode([String: JSONValue].self, from: params)) ?? [:]
        guard let key = object["key"]?.stringValue else { return .failure(.init("bad_params", "missing key")) }
        do {
            switch method {
            case "shell.secret.get":
                // The UI can write secrets but never read them back.
                guard caller == .backend else {
                    return .failure(.init("forbidden", "secrets are write-only from the UI"))
                }
                return .success(
                    try JSONEncoder().encode(secrets.get(app: appID, key: key).map(JSONValue.string) ?? .null))
            case "shell.secret.set":
                guard let value = object["value"]?.stringValue else {
                    return .failure(.init("bad_params", "missing value"))
                }
                try secrets.set(app: appID, key: key, value: value)
                return .success(Data("null".utf8))
            case "shell.secret.delete":
                try secrets.delete(app: appID, key: key)
                return .success(Data("null".utf8))
            default:
                return .failure(.init("unknown_method", method))
            }
        } catch {
            return .failure(.init("secret_failed", "\(error)"))
        }
    }
}
