import ShellCore
import SwiftUI

public struct AppIconView: View {
    private let app: AppDescriptor
    private let size: CGFloat

    public init(_ app: AppDescriptor, size: CGFloat = IconSize.launcher) {
        self.app = app
        self.size = size
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: Radius.icon(size), style: .continuous)
            .fill(
                LinearGradient(
                    colors: [app.tint.color, app.tint.color.opacity(0.65)], startPoint: .topLeading,
                    endPoint: .bottomTrailing)
            )
            .overlay {
                Image(systemName: app.symbolName)
                    .font(.system(size: size * IconSize.symbolRatio, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
    }
}

#Preview {
    AppIconView(AppDescriptor(id: "preview", name: "Preview", symbolName: "star.fill", tint: .blue, category: ""))
        .padding()
}
