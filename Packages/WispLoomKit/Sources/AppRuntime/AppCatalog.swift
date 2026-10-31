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
