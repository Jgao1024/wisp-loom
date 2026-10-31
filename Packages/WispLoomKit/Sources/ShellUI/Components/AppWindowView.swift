import ShellCore
import SwiftUI

/// Content of an app window: renders the app's UI tree with native controls.
public struct AppWindowView: View {
    let state: ShellState
    let tree: UITree
    let events: UIEvents

    public init(state: ShellState, tree: UITree, events: UIEvents) {
        self.state = state
        self.tree = tree
        self.events = events
    }

    public var body: some View {
        Group {
            if let root = tree.root { NodeView(node: root) } else { ProgressView().controlSize(.small) }
        }
        .environment(\.uiEvents, events)
        .environment(\.locale, state.language.locale)
    }
}
