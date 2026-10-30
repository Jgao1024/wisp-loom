import ShellCore
import SwiftUI

/// macOS Launchpad-like style: search field, category chips, icon grid.
struct GridLauncher: View {
    let apps: [AppDescriptor]
    let send: (ShellAction) -> Void

    @State private var query = ""
    @State private var category: String?
    @FocusState private var searchFocused: Bool

    private var categories: [String] {
        var seen = Set<String>()
        return apps.map(\.category).filter { seen.insert($0).inserted }
    }
    private var results: [AppDescriptor] { apps.matching(query, category: category) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            searchField
            categoryChips
            Divider()
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: Spacing.l)], spacing: Spacing.xl) {
                    ForEach(results) { app in
                        Button {
                            send(.openApp(app.id))
                        } label: {
                            VStack(spacing: Spacing.s) {
                                AppIconView(app)
                                Text(LocalizedStringKey(app.name)).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, Spacing.s)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 840, height: 560)
        .shellPanel()
        .onExitCommand { send(.hideLauncher) }
        .onAppear { searchFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .font(.title2)
                .focused($searchFocused)
                .onSubmit { results.first.map { send(.openApp($0.id)) } }
            Menu {
                Button("Settings…") { send(.openSettings) }
                Button("Quit") { send(.quit) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                ForEach(categories, id: \.self) { name in
                    Button(LocalizedStringKey(name)) { category = category == name ? nil : name }
                        .buttonStyle(.plain)
                        .padding(.horizontal, Spacing.m)
                        .padding(.vertical, Spacing.xs)
                        .background(
                            category == name ? Color.accentColor.opacity(0.6) : .white.opacity(0.1), in: Capsule())
                }
            }
        }
    }
}

#Preview {
    GridLauncher(apps: AppDescriptor.samples, send: { _ in })
}
