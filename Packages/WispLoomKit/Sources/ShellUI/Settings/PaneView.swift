import ShellCore
import SwiftUI

public enum SettingsMetrics {
    /// Every settings pane is this wide, so the window only animates in height when switching panes.
    public static let paneWidth: CGFloat = 480
}

/// One `<Pane>` of an app's settings: a grouped form of its sections and controls.
public struct PaneView: View {
    let node: UINode
    let state: ShellState
    let events: UIEvents

    public init(node: UINode, state: ShellState, events: UIEvents) {
        self.node = node
        self.state = state
        self.events = events
    }

    public var body: some View {
        Form { Children(nodes: node.children) }
            .formStyle(.grouped)
            .frame(width: SettingsMetrics.paneWidth)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.uiEvents, events)
            .environment(\.locale, state.language.locale)
    }
}
