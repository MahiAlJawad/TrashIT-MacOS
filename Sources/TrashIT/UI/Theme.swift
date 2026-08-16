import SwiftUI

extension SafetyLevel {
    var color: Color {
        switch self {
        case .regeneratable: .green
        case .redownloadable: .blue
        case .reviewRequired: .orange
        case .irreplaceable: .red
        }
    }
}

extension CleanupCategory {
    var color: Color {
        switch self {
        case .xcode, .developerCaches: .indigo
        case .simulators: .cyan
        case .appCaches: .purple
        case .logs: .gray
        case .downloads, .archives: .blue
        case .oldFiles: .orange
        case .duplicates: .mint
        case .backups: .brown
        case .cloudCopies: .teal
        case .trash, .appLeftovers: .red
        }
    }
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5)
            }
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
}
