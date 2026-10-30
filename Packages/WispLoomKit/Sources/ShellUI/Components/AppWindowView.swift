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
    AppWindowView(app: AppDescriptor.samples[0]).frame(width: 480, height: 320)
}
