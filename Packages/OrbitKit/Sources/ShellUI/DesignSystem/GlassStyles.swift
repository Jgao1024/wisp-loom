import SwiftUI

extension View {
    public func shellPanel() -> some View {
        glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
    }
}
