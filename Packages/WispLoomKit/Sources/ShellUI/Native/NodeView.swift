import ShellCore
import SwiftUI

/// Maps one UI node to a system control. Each node is its own `@Observable`, so a patch re-evaluates only
/// the views that read the props or children that changed.
struct NodeView: View {
    let node: UINode

    var body: some View {
        switch node.type {
        case "App": Children(nodes: node.children)
        case "Window": WindowNode(node: node)
        case "Split": SplitNode(node: node)
        case "Stack": StackNode(node: node)
        case "Spacer": Spacer()
        case "Divider": Divider()
        case "Text": TextNode(node: node)
        case "Empty": EmptyNode(node: node)
        case "Button": ButtonNode(node: node)
        case "Menu": MenuNode(node: node)
        case "List": ListNode(node: node)
        case "Section": SectionNode(node: node)
        case "Row": RowNode(node: node)
        case "SidebarTiles": TilesNode(node: node)
        default: EmptyView()  // Command, Settings and toolbar items are consumed by their parents
        }
    }
}

struct Children: View {
    let nodes: [UINode]

    var body: some View {
        ForEach(nodes) { NodeView(node: $0) }
    }
}

extension UINode {
    /// Everything except toolbar declarations, which attach to the container instead.
    var content: [UINode] { children.filter { $0.type != "Toolbar" } }
}

extension View {
    @ViewBuilder func titled(by node: UINode) -> some View {
        if let title = node.string("title") {
            navigationTitle(title).navigationSubtitle(node.string("subtitle") ?? "")
        } else {
            self
        }
    }
}

// MARK: - Layout

struct WindowNode: View {
    let node: UINode

    var body: some View {
        Children(nodes: node.content)
            .toolbar { ToolbarNodes(parent: node) }
            .titled(by: node)
    }
}

struct SplitNode: View {
    let node: UINode

    var body: some View {
        if node.props["query"] != nil {
            SyncedText(node: node, prop: "query", event: "onQuery") { query in
                Columns(node: node).searchable(text: query, prompt: Text(verbatim: node.string("placeholder") ?? ""))
            }
        } else {
            Columns(node: node)
        }
    }
}

private struct Columns: View {
    let node: UINode

    private func column(_ type: String) -> some View {
        Group {
            if let column = node.children.first(where: { $0.type == type }) { ColumnNode(node: column) }
        }
    }

    var body: some View {
        if node.number("columns") == 3 {
            NavigationSplitView {
                column("Sidebar")
            } content: {
                column("Content")
            } detail: {
                column("Detail")
            }
        } else {
            NavigationSplitView {
                column("Sidebar")
            } detail: {
                column("Detail")
            }
        }
    }
}

struct ColumnNode: View {
    let node: UINode

    var body: some View {
        VStack(spacing: 0) { Children(nodes: node.content) }
            .toolbar { ToolbarNodes(parent: node) }
            .titled(by: node)
    }
}

struct StackNode: View {
    let node: UINode

    var body: some View {
        let spacing = Spacing.stack(node.string("spacing"))
        if node.string("axis") == "horizontal" {
            HStack(spacing: spacing) { Children(nodes: node.children) }
        } else {
            VStack(alignment: .leading, spacing: spacing) { Children(nodes: node.children) }
        }
    }
}

// MARK: - Toolbar

/// `Toolbar` children: `ToolbarGroup` (one capsule), `ToolbarSpacer`, or a bare Button / Menu.
struct ToolbarNodes: ToolbarContent {
    let parent: UINode

    var body: some ToolbarContent {
        ForEach(parent.children.filter { $0.type == "Toolbar" }.flatMap(\.children)) { item in
            if item.type == "ToolbarSpacer" {
                ToolbarSpacer(.fixed)
            } else {
                ToolbarItemGroup(placement: item.string("placement") == "principal" ? .principal : .primaryAction) {
                    Children(nodes: item.type == "ToolbarGroup" ? item.children : [item])
                }
            }
        }
    }
}

// MARK: - Controls

struct TextNode: View {
    let node: UINode

    private var font: Font {
        switch node.string("style") {
        case "title": .title
        case "headline": .headline
        case "caption": .caption
        default: .body
        }
    }

    var body: some View {
        let text = Text(verbatim: node.string("text") ?? "").font(font)
        let styled = node.string("style") == "secondary" || node.string("style") == "caption"
        Group {
            if node.bool("selectable") { text.textSelection(.enabled) } else { text.textSelection(.disabled) }
        }
        .foregroundStyle(styled ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
    }
}

struct EmptyNode: View {
    let node: UINode

    var body: some View {
        let title = Text(verbatim: node.string("title") ?? "")
        let description = Text(verbatim: node.string("description") ?? "")
        if let symbol = node.string("symbol") {
            ContentUnavailableView {
                Label {
                    title
                } icon: {
                    Image(systemName: symbol)
                }
            } description: {
                description
            }
        } else {
            ContentUnavailableView {
                title
            } description: {
                description
            }
        }
    }
}

private struct Titled: View {
    let node: UINode

    var body: some View {
        switch (node.string("title"), node.string("symbol")) {
        case (let title?, let symbol?):
            Label {
                Text(verbatim: title)
            } icon: {
                Image(systemName: symbol)
            }
        case (let title?, nil): Text(verbatim: title)
        case (nil, let symbol?): Image(systemName: symbol)
        default: EmptyView()
        }
    }
}

struct ButtonNode: View {
    let node: UINode
    @Environment(\.uiEvents) private var events

    var body: some View {
        let button = Button {
            events.send(node.handler("onAction"))
        } label: {
            Titled(node: node)
        }
        .disabled(node.bool("disabled"))
        if node.bool("prominent") { button.buttonStyle(.glassProminent) } else { button }
    }
}

struct MenuNode: View {
    let node: UINode

    var body: some View {
        Menu {
            Children(nodes: node.children)
        } label: {
            Titled(node: node)
        }
    }
}

// MARK: - Lists

struct ListNode: View {
    let node: UINode
    @Environment(\.uiEvents) private var events

    var body: some View {
        List(
            selection: Binding(
                get: { node.string("selection") },
                set: { events.send(node.handler("onSelect"), $0.map(JSONValue.string) ?? .null) })
        ) {
            Children(nodes: node.children)
        }
    }
}

struct SectionNode: View {
    let node: UINode

    var body: some View {
        Section {
            Children(nodes: node.children)
        } header: {
            if let title = node.string("title") { Text(verbatim: title) }
        }
    }
}

struct RowNode: View {
    let node: UINode

    var body: some View {
        let title = VStack(alignment: .leading) {
            Text(verbatim: node.string("title") ?? "")
            if let subtitle = node.string("subtitle") {
                Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        Group {
            if let symbol = node.string("symbol") {
                Label {
                    title
                } icon: {
                    Image(systemName: symbol)
                }
            } else {
                title
            }
        }
        .badge(node.props["badge"].map { Text(verbatim: $0.display) })
        .tag(node.string("value") ?? node.id)
    }
}

extension JSONValue {
    fileprivate var display: String {
        switch self {
        case .string(let value): value
        case .number(let value): value.rounded() == value ? String(Int(value)) : String(value)
        case .bool(let value): String(value)
        default: ""
        }
    }
}

struct TilesNode: View {
    let node: UINode

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.s) {
            ForEach(node.children) { TileNode(node: $0) }
        }
        .padding(Spacing.s)
    }
}

struct TileNode: View {
    let node: UINode
    @Environment(\.uiEvents) private var events

    var body: some View {
        let tint = (node.string("tint").flatMap(AppTint.init(rawValue:)) ?? .accent).color
        Button {
            events.send(node.handler("onAction"))
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Image(systemName: node.string("symbol") ?? "circle").font(.title2).foregroundStyle(tint)
                    Spacer()
                    if let count = node.props["count"] { Text(verbatim: count.display).font(.title2.bold()) }
                }
                Text(verbatim: node.string("title") ?? "").font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
