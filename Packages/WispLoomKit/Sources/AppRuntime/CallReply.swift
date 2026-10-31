import Foundation

/// One answer to a `call`; payloads are raw JSON so they cross threads as plain bytes.
public enum CallReply: Sendable {
    case event(Data)
    case result(Data)
    case failure(code: String, message: String)
}

public struct CallFailure: Error, Sendable {
    public let code: String
    public let message: String

    public init(_ code: String, _ message: String) {
        self.code = code
        self.message = message
    }
}
