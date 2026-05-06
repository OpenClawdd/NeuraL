import Foundation

struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    let role: MessageRole
    var content: String
    var timestamp: Date = Date()
    var reasoningTrace: String?
    var traceSummary: String?
    var traceWasTruncated: Bool = false
    var traceTokenEstimate: Int = 0

    enum MessageRole: String, Codable, Sendable {
        case user, assistant, system
    }

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        reasoningTrace: String? = nil,
        traceSummary: String? = nil,
        traceWasTruncated: Bool = false,
        traceTokenEstimate: Int = 0
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.reasoningTrace = reasoningTrace
        self.traceSummary = traceSummary
        self.traceWasTruncated = traceWasTruncated
        self.traceTokenEstimate = traceTokenEstimate
    }

    static func userMessage(_ text: String) -> ChatMessage { .init(role: .user, content: text) }
    static func assistantMessage(_ text: String, trace: ParsedGeneration? = nil) -> ChatMessage {
        .init(
            role: .assistant,
            content: text,
            reasoningTrace: trace?.reasoningTrace,
            traceSummary: ThinkTagParser.traceSummary(for: trace?.reasoningTrace),
            traceWasTruncated: trace?.traceWasTruncated ?? false,
            traceTokenEstimate: trace?.traceTokenEstimate ?? 0
        )
    }
    static func systemPrompt(_ text: String) -> ChatMessage { .init(role: .system, content: text) }
}

struct Conversation: Codable, Sendable {
    var id: UUID = UUID()
    var messages: [ChatMessage] = []

    var conversationalMessages: [ChatMessage] { messages.filter { $0.role != .system } }
}
