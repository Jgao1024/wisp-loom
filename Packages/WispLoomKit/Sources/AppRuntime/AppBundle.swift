import Foundation
import ShellCore

/// An app directory on disk with its decoded manifest.
public struct AppBundle: Sendable, Hashable {
    public let directory: URL
    public let manifest: Manifest

    public init(directory: URL, manifest: Manifest) {
        self.directory = directory
        self.manifest = manifest
    }

    public var scriptURL: URL { directory.appendingPathComponent(manifest.ui) }
}
