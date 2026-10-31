import ShellCore
import SwiftUI

public struct SettingsView: View {
    let state: ShellState
    let send: (ShellAction) -> Void

    public init(state: ShellState, send: @escaping (ShellAction) -> Void) {
        self.state = state
        self.send = send
    }

    public var body: some View {
        Form {
            LabeledContent("Shortcut") {
                ShortcutRecorder(hotKey: Binding(get: { state.hotKey }, set: { send(.setHotKey($0)) }))
            }
            Picker("Language", selection: Binding(get: { state.language }, set: { send(.setLanguage($0)) })) {
                ForEach(Language.allCases) { Text($0.name).tag($0) }
            }
            Picker(
                "Launcher style", selection: Binding(get: { state.launcherStyle }, set: { send(.setLauncherStyle($0)) })
            ) {
                ForEach(LauncherStyle.allCases) { Text($0.title).tag($0) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.locale, state.language.locale)
    }
}

#Preview {
    SettingsView(state: ShellState(apps: []), send: { _ in })
}
