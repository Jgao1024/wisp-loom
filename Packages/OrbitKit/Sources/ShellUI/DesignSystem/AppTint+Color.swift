import ShellCore
import SwiftUI

extension AppTint {
    public var color: Color {
        switch self {
        case .accent: .accentColor
        case .blue: .blue
        case .green: .green
        case .orange: .orange
        case .pink: .pink
        case .purple: .purple
        case .red: .red
        case .teal: .teal
        case .yellow: .yellow
        case .gray: .gray
        }
    }
}
