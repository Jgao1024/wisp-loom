import AppRuntime
import Foundation
import ShellCore
import ShellPlatform

/// Development only (`WISP_APPS` set): turns file changes under the apps directory into reloads.
/// The watcher exists only in that mode, so release builds never touch FSEvents.
@MainActor
final class HotReloader {
    private var watcher: DirectoryWatcher?

    init?(root: URL, registry: AppRegistry, onCatalogChange: @escaping @MainActor () -> Void) {
        watcher = DirectoryWatcher(path: root) { [registry] paths in
            var changes = Set<AppChange>()
            for path in paths {
                if let change = AppCatalog.change(at: path, in: registry.bundles) { changes.insert(change) }
            }
            if changes.contains(.manifest) { onCatalogChange() }
            for change in changes { registry.apply(change) }
        }
        if watcher == nil { return nil }
    }
}
