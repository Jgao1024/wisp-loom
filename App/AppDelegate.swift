import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let root = CompositionRoot()

    func applicationDidFinishLaunching(_ notification: Notification) { root.start() }
    func applicationWillTerminate(_ notification: Notification) { root.stop() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
