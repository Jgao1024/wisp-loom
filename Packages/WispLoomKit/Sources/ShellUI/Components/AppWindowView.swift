import ShellCore
import SwiftUI

/// Stand-in window content until plugins render their own UI.
public struct AppWindowView: View {
    private let app: AppDescriptor

    public init(app: AppDescriptor) { self.app = app }

    public var body: some View {
        ContentUnavailableView(app.name, systemImage: app.symbolName)
    }
}

#Preview {
    AppWindowView(
        app: AppDescriptor(id: "preview", name: "Preview", symbolName: "star.fill", tint: .blue, category: "")
    ).frame(width: 480, height: 320)
}
