import ShellCore
import SwiftUI

public struct LauncherView: View {
    let state: ShellState
    let send: (ShellAction) -> Void

    public init(state: ShellState, send: @escaping (ShellAction) -> Void) {
        self.state = state
        self.send = send
    }

    public var body: some View {
        Group {
            switch state.launcherStyle {
            case .grid: GridLauncher(apps: state.apps, send: send)
            }
        }
        .environment(\.locale, state.language.locale)
    }
}

extension LauncherStyle {
    public var title: LocalizedStringKey {
        switch self {
        case .grid: "Grid"
        }
    }
}
