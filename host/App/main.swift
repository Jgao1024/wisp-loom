import AppKit

// Plain AppKit entry point: SwiftUI's App lifecycle would own (and overwrite) the main menu.
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    NSApplication.shared.delegate = delegate
    NSApplication.shared.run()
}
