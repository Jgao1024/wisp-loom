// AppKit is needed here: SwiftUI key events don't expose raw key codes.
import AppKit
import ShellCore
import SwiftUI

struct ShortcutRecorder: View {
    @Binding var hotKey: HotKey
    @State private var isRecording = false
    @State private var monitor: Any?

    private static let escape: UInt16 = 53
    private static let names: [UInt16: String] = [
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    var body: some View {
        Button {
            isRecording.toggle()
        } label: {
            if isRecording { Text("Press shortcut…") } else { Text(verbatim: hotKey.label) }
        }
        .onChange(of: isRecording) { _, recording in
            if recording { startMonitoring() } else { stopMonitoring() }
        }
        .onDisappear { isRecording = false }
    }

    private func startMonitoring() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            capture(event)
            return nil
        }
    }

    private func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Requires at least one modifier so plain typing can never become the shortcut.
    private func capture(_ event: NSEvent) {
        defer { isRecording = false }
        let modifiers = HotKey.Modifiers(event.modifierFlags)
        let key = Self.names[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? ""
        guard event.keyCode != Self.escape, !modifiers.isEmpty, !key.isEmpty else { return }
        hotKey = HotKey(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: key)
    }
}

extension HotKey.Modifiers {
    fileprivate init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.command) { insert(.command) }
    }
}

#Preview {
    ShortcutRecorder(hotKey: .constant(.default)).padding()
}
