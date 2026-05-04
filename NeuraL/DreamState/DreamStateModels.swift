import Foundation

struct DreamCard: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var title: String
    var summary: String
    var nextAction: String
    var rememberedTheme: String?
    var sourceMessageID: UUID
    var confidence: Double
    var tags: [String]
}

struct DreamStateSettings: Codable, Equatable, Sendable {
    enum TraceVisibility: String, Codable, CaseIterable, Identifiable, Sendable {
        case always = "Always"
        case collapsed = "Collapsed"
        case never = "Never"

        var id: String { rawValue }
    }

    enum Retention: String, Codable, CaseIterable, Identifiable, Sendable {
        case fifty = "50"
        case hundred = "100"
        case unlimited = "Unlimited"

        var id: String { rawValue }

        var limit: Int? {
            switch self {
            case .fifty: return 50
            case .hundred: return 100
            case .unlimited: return nil
            }
        }
    }

    var traceVisibility: TraceVisibility = .collapsed
    var rawTraceAccess: Bool = false
    var autoCreateDreams: Bool = true
    var retention: Retention = .hundred
}
