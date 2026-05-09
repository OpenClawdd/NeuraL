import Foundation

struct ImageAttachment: Codable, Sendable, Equatable {
    var filename: String
    var data: Data
}

struct FunctionCallRecord: Codable, Sendable, Equatable {
    var toolName: String
    var isSuccess: Bool
    var durationSeconds: Double
}

struct RAGSourceRecord: Codable, Sendable, Equatable {
    var documentName: String
    var chunkIndex: Int
    var similarity: Double
}

struct MessageTokenInfo: Codable, Sendable, Equatable {
    var promptTokenCount: Int
    var generationTokenCount: Int
    var totalTokenCount: Int { promptTokenCount + generationTokenCount }
}

struct GenerationMetadata: Codable, Sendable, Equatable {
    var tokensPerSecond: Double
    var tokensGenerated: Int

    static let empty = GenerationMetadata(tokensPerSecond: 0, tokensGenerated: 0)
}

struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    let role: MessageRole
    var content: String
    var timestamp: Date = Date()
    var reasoningTrace: String?
    var traceSummary: String?
    var traceWasTruncated: Bool = false
    var traceTokenEstimate: Int = 0

    var tokenInfo: MessageTokenInfo?
    var functionCalls: [FunctionCallRecord]?
    var ragSources: [RAGSourceRecord]?
    var thinkingText: String?
    var thinkingDurationSeconds: Double = 0
    var generationMetadata: GenerationMetadata?
    var isInKVCache: Bool = true
    var imageAttachments: [ImageAttachment]?

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
        traceTokenEstimate: Int = 0,
        tokenInfo: MessageTokenInfo? = nil,
        generationMetadata: GenerationMetadata? = nil,
        thinkingText: String? = nil,
        thinkingDurationSeconds: Double = 0,
        isInKVCache: Bool = true,
        imageAttachments: [ImageAttachment]? = nil,
        functionCalls: [FunctionCallRecord]? = nil,
        ragSources: [RAGSourceRecord]? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.reasoningTrace = reasoningTrace
        self.traceSummary = traceSummary
        self.traceWasTruncated = traceWasTruncated
        self.traceTokenEstimate = traceTokenEstimate
        self.tokenInfo = tokenInfo
        self.generationMetadata = generationMetadata
        self.thinkingText = thinkingText
        self.thinkingDurationSeconds = thinkingDurationSeconds
        self.isInKVCache = isInKVCache
        self.imageAttachments = imageAttachments
        self.functionCalls = functionCalls
        self.ragSources = ragSources
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
    static func assistantMessage(_ text: String, tokenInfo: MessageTokenInfo? = nil, metadata: GenerationMetadata? = nil) -> ChatMessage {
        .init(role: .assistant, content: text, tokenInfo: tokenInfo, generationMetadata: metadata)
    }
}

struct Conversation: Codable, Sendable {
    var id: UUID = UUID()
    var messages: [ChatMessage] = []

    init(systemPrompt: String? = nil) {
        if let prompt = systemPrompt {
            messages.append(.systemPrompt(prompt))
        }
    }

    mutating func append(_ message: ChatMessage) {
        messages.append(message)
    }

    var conversationalMessages: [ChatMessage] { messages.filter { $0.role != .system } }

    var title: String? {
        messages.first { $0.role == .user }?.content
    }

    var lastUpdatedAt: Date {
        messages.last?.timestamp ?? Date()
    }

    var systemPrompt: ChatMessage? {
        messages.first { $0.role == .system }
    }

    var turnCount: Int {
        messages.filter { $0.role == .user }.count
    }
}
