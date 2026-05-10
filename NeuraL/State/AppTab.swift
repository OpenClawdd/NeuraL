import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    var id: String { rawValue }

    case chat
    case models
    case knowledge
    case lab
    case system

    var title: String {
        switch self {
        case .chat: return "Chat"
        case .models: return "Models"
        case .knowledge: return "Knowledge"
        case .lab: return "Lab"
        case .system: return "System"
        }
    }

    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        case .models: return "cube"
        case .knowledge: return "doc.text.magnifyingglass"
        case .lab: return "sparkles"
        case .system: return "cpu"
        }
    }
}
