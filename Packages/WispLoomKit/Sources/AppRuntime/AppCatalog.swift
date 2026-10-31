import Foundation
import ShellCore

public enum AppCatalog {
    /// Every `<root>/<name>/manifest.json` that decodes. Roots are searched in order and the first
    /// app with a given id wins, so a built-in app cannot be shadowed by a stray copy.
    public static func scan(_ roots: [URL], log: (String) -> Void = { _ in }) -> [AppBundle] {
        var found: [AppBundle] = []
        var seen = Set<AppID>()
        let manager = FileManager.default
        for root in roots {
            let entries = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            for directory in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let file = directory.appendingPathComponent("manifest.json")
                guard let data = try? Data(contentsOf: file) else { continue }
                do {
                    let manifest = try Manifest.decode(data)
                    if seen.insert(manifest.id).inserted {
                        found.append(AppBundle(directory: directory, manifest: manifest))
                    }
                } catch {
                    log("skipping \(file.path): \(error)")
                }
            }
        }
        return found
    }
}

/// What a changed file means for a running app (dev-time hot reload, docs/02-app-protocol.md §4).
public enum AppChange: Hashable, Sendable {
    case script(AppID)
    case backend(AppID)
    /// Any manifest: the catalog is rescanned, which also picks up new or removed apps.
    case manifest
}

extension AppCatalog {
    /// `path` must be a real path (FSEvents reports those); bundle directories are resolved here.
    public static func change(at path: String, in bundles: [AppBundle]) -> AppChange? {
        if path.hasSuffix("/manifest.json") { return .manifest }
        for bundle in bundles {
            let directory = bundle.directory.resolvingSymlinksInPath().path + "/"
            guard path.hasPrefix(directory) else { continue }
            let relative = String(path.dropFirst(directory.count))
            if relative == bundle.manifest.ui { return .script(bundle.manifest.id) }
            if relative.hasPrefix("backend/") { return .backend(bundle.manifest.id) }
        }
        return nil
    }
}
