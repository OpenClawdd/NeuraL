import Foundation


struct MessageTokenInfo: Codable, Sendable {
    var promptTokenCount: Int = 0
    var generationTokenCount: Int = 0
    var totalTokenCount: Int { promptTokenCount + generationTokenCount }
    static func estimate(from text: String, role: MessageRole) -> MessageTokenInfo {
        let tokens = max(1, Int(Double(text.count) / 3.8))
        return MessageTokenInfo(promptTokenCount: role == .assistant ? 0 : tokens, generationTokenCount: role == .assistant ? tokens : 0)
    }
}
struct GenerationMetadata: Codable, Sendable {
    var tokensGenerated: Int = 0
    var durationSeconds: TimeInterval = 0
    var tokensPerSecond: Double = 0
    var promptProcessingSeconds: TimeInterval = 0
    var peakMemoryBytes: UInt64 = 0
    var stopReason: String = ""
    static var placeholder: GenerationMetadata { GenerationMetadata() }
}
enum DeviceCapabilityTier: String, Codable, Sendable { case limited, standard, premium, extended }
struct ImageAttachment: Codable, Sendable {
    var id: UUID = UUID()
    var thumbnailData: Data = Data()
    var fullImageData: Data = Data()
    var caption: String? = nil
}
struct FunctionCallRecord: Codable, Sendable {
    var toolName: String = ""
    var parameters: [String: String] = [:]
    var result: String = ""
}
struct RAGSourceCitation: Codable, Sendable {
    var excerpt: String = ""
    var documentID: UUID = UUID()
    var chunkIndex: Int = 0
}
struct ChatMessage: Identifiable, Codable, Equatable {
    var id = UUID()
    let role: MessageRole
    var content: String
    var timestamp = Date()
    var tokenInfo: MessageTokenInfo? = nil
    var thinkingText: String? = nil
    var thinkingDurationSeconds: TimeInterval? = nil
    var isInKVCache: Bool = true
    var imageAttachments: [ImageAttachment]? = nil
    var functionCalls: [FunctionCallRecord]? = nil
    var ragSources: [RAGSourceCitation]? = nil
    var generationMetadata: GenerationMetadata? = nil

    enum MessageRole: String, Codable { case user, assistant, system }

    static func userMessage(_ text: String) -> ChatMessage { ChatMessage(role: .user, content: text) }
    static func assistantMessage(_ text: String) -> ChatMessage { ChatMessage(role: .assistant, content: text) }
    static func systemPrompt(_ text: String) -> ChatMessage { ChatMessage(role: .system, content: text) }
}

class Conversation: Codable {
    var id: UUID = UUID()
    var title: String? = nil
    var lastUpdatedAt: Date = Date()
    var systemPrompt: ChatMessage? { messages.first(where: { class Conversation: Codable {.role == .system }) }
    var conversationalMessages: [ChatMessage] { messages.filter { class Conversation: Codable {.role != .system } }
    mutating func evictOldestTurn() -> Int {
        guard let firstUser = messages.firstIndex(where: { class Conversation: Codable {.role == .user }),
              let firstAssistant = messages[firstUser...].firstIndex(where: { class Conversation: Codable {.role == .assistant }) else { return 0 }
        let freed = (messages[firstUser].tokenInfo?.totalTokenCount ?? 0) + (messages[firstAssistant].tokenInfo?.totalTokenCount ?? 0)
        messages.remove(at: firstAssistant)
        messages.remove(at: firstUser)
        return freed
    }
    var messages: [ChatMessage] = []
}

