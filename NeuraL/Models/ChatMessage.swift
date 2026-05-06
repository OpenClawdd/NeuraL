import Foundation

// MARK: - Phase 6 Supporting Types

struct FunctionCallRecord: Sendable, Identifiable, Codable {
    let id: UUID
    let toolName: String
    let parameters: String
    let result: String?
    let isSuccess: Bool
    let durationSeconds: Double
}

struct RAGSourceCitation: Sendable, Identifiable, Codable {
    let id: UUID
    let documentName: String
    let chunkIndex: Int
    let similarity: Float
    let snippet: String
}

// MARK: - Message Role

enum MessageRole: String, Sendable, Codable, CaseIterable, CustomStringConvertible {
    case system
    case user
    case assistant

    var description: String { rawValue }

    var isEvictable: Bool {
        switch self {
        case .system: return false
        case .user, .assistant: return true
        }
    }
}

// MARK: - Token / Generation Metadata

struct MessageTokenInfo: Sendable, Codable, Equatable {
    let promptTokenCount: Int
    let generationTokenCount: Int

    var totalTokenCount: Int { promptTokenCount + generationTokenCount }

    static func estimate(from text: String, role: MessageRole) -> MessageTokenInfo {
        let estimatedContentTokens = max(1, Int(Double(text.count) / 3.8))
        let templateOverhead = 8
        return MessageTokenInfo(
            promptTokenCount: estimatedContentTokens + templateOverhead,
            generationTokenCount: 0
        )
    }

    static let zero = MessageTokenInfo(promptTokenCount: 0, generationTokenCount: 0)
}

struct GenerationMetadata: Sendable, Codable, Equatable {
    let tokensGenerated: Int
    let durationSeconds: Double
    let promptProcessingSeconds: Double
    let peakMemoryBytes: UInt64
    let stopReason: StopReason

    var tokensPerSecond: Double {
        guard durationSeconds > 0 else { return 0 }
        return Double(tokensGenerated) / durationSeconds
    }

    enum StopReason: String, Sendable, Codable {
        case endOfGenerationToken
        case stopTokenMatched
        case maxTokensReached
        case cancelled
        case error
    }

    static let empty = GenerationMetadata(
        tokensGenerated: 0,
        durationSeconds: 0,
        promptProcessingSeconds: 0,
        peakMemoryBytes: 0,
        stopReason: .maxTokensReached
    )
}

// MARK: - Chat Message

struct ChatMessage: Sendable, Identifiable, Codable {
    let id: UUID
    let role: MessageRole
    var content: String
    let timestamp: Date
    var tokenInfo: MessageTokenInfo
    let generationMetadata: GenerationMetadata?
    let thinkingText: String?
    let thinkingDurationSeconds: Double
    var isInKVCache: Bool
    let imageAttachments: [ImageAttachment]?
    let functionCalls: [FunctionCallRecord]?
    let ragSources: [RAGSourceCitation]?

    var reasoningTrace: String?
    var traceSummary: String?
    var traceWasTruncated: Bool
    var traceTokenEstimate: Int

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        tokenInfo: MessageTokenInfo? = nil,
        generationMetadata: GenerationMetadata? = nil,
        thinkingText: String? = nil,
        thinkingDurationSeconds: Double = 0,
        isInKVCache: Bool = false,
        imageAttachments: [ImageAttachment]? = nil,
        functionCalls: [FunctionCallRecord]? = nil,
        ragSources: [RAGSourceCitation]? = nil,
        reasoningTrace: String? = nil,
        traceSummary: String? = nil,
        traceWasTruncated: Bool = false,
        traceTokenEstimate: Int = 0
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.tokenInfo = tokenInfo ?? .estimate(from: content, role: role)
        self.generationMetadata = generationMetadata
        self.thinkingText = thinkingText
        self.thinkingDurationSeconds = thinkingDurationSeconds
        self.isInKVCache = isInKVCache
        self.imageAttachments = imageAttachments
        self.functionCalls = functionCalls
        self.ragSources = ragSources
        self.reasoningTrace = reasoningTrace ?? thinkingText
        self.traceSummary = traceSummary ?? ThinkTagParser.traceSummary(for: reasoningTrace ?? thinkingText)
        self.traceWasTruncated = traceWasTruncated
        self.traceTokenEstimate = traceTokenEstimate
    }



    private enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp, tokenInfo, generationMetadata, thinkingText, thinkingDurationSeconds, isInKVCache, imageAttachments, functionCalls, ragSources, reasoningTrace, traceSummary, traceWasTruncated, traceTokenEstimate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let role = try container.decode(MessageRole.self, forKey: .role)
        let content = try container.decode(String.self, forKey: .content)
        let reasoningTrace = try container.decodeIfPresent(String.self, forKey: .reasoningTrace)
        let legacyThinkingText = try container.decodeIfPresent(String.self, forKey: .thinkingText)
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            role: role,
            content: content,
            timestamp: try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date(),
            tokenInfo: try container.decodeIfPresent(MessageTokenInfo.self, forKey: .tokenInfo) ?? .estimate(from: content, role: role),
            generationMetadata: try container.decodeIfPresent(GenerationMetadata.self, forKey: .generationMetadata),
            thinkingText: legacyThinkingText,
            thinkingDurationSeconds: try container.decodeIfPresent(Double.self, forKey: .thinkingDurationSeconds) ?? 0,
            isInKVCache: try container.decodeIfPresent(Bool.self, forKey: .isInKVCache) ?? false,
            imageAttachments: try container.decodeIfPresent([ImageAttachment].self, forKey: .imageAttachments),
            functionCalls: try container.decodeIfPresent([FunctionCallRecord].self, forKey: .functionCalls),
            ragSources: try container.decodeIfPresent([RAGSourceCitation].self, forKey: .ragSources),
            reasoningTrace: reasoningTrace ?? legacyThinkingText,
            traceSummary: try container.decodeIfPresent(String.self, forKey: .traceSummary),
            traceWasTruncated: try container.decodeIfPresent(Bool.self, forKey: .traceWasTruncated) ?? false,
            traceTokenEstimate: try container.decodeIfPresent(Int.self, forKey: .traceTokenEstimate) ?? 0
        )
    }

    static func systemPrompt(_ content: String) -> ChatMessage {
        ChatMessage(role: .system, content: content)
    }

    static func userMessage(_ content: String, imageAttachments: [ImageAttachment]? = nil) -> ChatMessage {
        ChatMessage(role: .user, content: content, imageAttachments: imageAttachments)
    }

    static func assistantMessage(_ text: String, trace: ParsedGeneration? = nil) -> ChatMessage {
        ChatMessage(
            role: .assistant,
            content: text,
            generationMetadata: .empty,
            thinkingText: trace?.reasoningTrace,
            isInKVCache: true,
            reasoningTrace: trace?.reasoningTrace,
            traceSummary: ThinkTagParser.traceSummary(for: trace?.reasoningTrace),
            traceWasTruncated: trace?.traceWasTruncated ?? false,
            traceTokenEstimate: trace?.traceTokenEstimate ?? 0
        )
    }

    static func assistantMessage(
        _ content: String,
        tokenInfo: MessageTokenInfo,
        metadata: GenerationMetadata?,
        thinkingText: String? = nil,
        thinkingDurationSeconds: Double = 0,
        functionCalls: [FunctionCallRecord]? = nil,
        ragSources: [RAGSourceCitation]? = nil,
        trace: ParsedGeneration? = nil
    ) -> ChatMessage {
        ChatMessage(
            role: .assistant,
            content: content,
            tokenInfo: tokenInfo,
            generationMetadata: metadata,
            thinkingText: thinkingText ?? trace?.reasoningTrace,
            thinkingDurationSeconds: thinkingDurationSeconds,
            isInKVCache: true,
            functionCalls: functionCalls,
            ragSources: ragSources,
            reasoningTrace: trace?.reasoningTrace ?? thinkingText,
            traceSummary: ThinkTagParser.traceSummary(for: trace?.reasoningTrace ?? thinkingText),
            traceWasTruncated: trace?.traceWasTruncated ?? false,
            traceTokenEstimate: trace?.traceTokenEstimate ?? 0
        )
    }

    func withTokenInfo(_ newTokenInfo: MessageTokenInfo) -> ChatMessage {
        var copy = self
        copy.tokenInfo = newTokenInfo
        return copy
    }

    func markInKVCache() -> ChatMessage {
        var copy = self
        copy.isInKVCache = true
        return copy
    }
}

// MARK: - Conversation

struct Conversation: Sendable, Codable {
    let id: UUID
    var title: String?
    var messages: [ChatMessage]
    let createdAt: Date
    var lastUpdatedAt: Date

    var systemPrompt: ChatMessage? { messages.first { $0.role == .system } }
    var conversationalMessages: [ChatMessage] { messages.filter { $0.role != .system } }
    var totalTokenCount: Int { messages.reduce(0) { $0 + $1.tokenInfo.totalTokenCount } }
    var turnCount: Int { conversationalMessages.filter { $0.role == .user }.count }
    var isEmpty: Bool { messages.isEmpty }
    var lastMessage: ChatMessage? { messages.last }

    init(
        id: UUID = UUID(),
        title: String? = nil,
        messages: [ChatMessage] = [],
        createdAt: Date = Date(),
        lastUpdatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.lastUpdatedAt = lastUpdatedAt
    }

    init(systemPrompt: String) {
        self.init(messages: [.systemPrompt(systemPrompt)])
    }



    private enum CodingKeys: String, CodingKey {
        case id, title, messages, createdAt, lastUpdatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let messages = try container.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
        let createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            title: try container.decodeIfPresent(String.self, forKey: .title),
            messages: messages,
            createdAt: createdAt,
            lastUpdatedAt: try container.decodeIfPresent(Date.self, forKey: .lastUpdatedAt) ?? createdAt
        )
    }

    mutating func append(_ message: ChatMessage) {
        messages.append(message)
        lastUpdatedAt = Date()
        if title == nil, message.role == .user {
            title = String(message.content.prefix(60))
        }
    }

    mutating func setSystemPrompt(_ content: String) {
        if let index = messages.firstIndex(where: { $0.role == .system }) {
            messages[index] = .systemPrompt(content)
        } else {
            messages.insert(.systemPrompt(content), at: 0)
        }
        lastUpdatedAt = Date()
    }

    mutating func removeMessage(id: UUID) {
        messages.removeAll { $0.id == id }
        lastUpdatedAt = Date()
    }

    @discardableResult
    mutating func evictOldestTurn() -> Int {
        guard let firstUserIndex = messages.firstIndex(where: { $0.role == .user }) else { return 0 }
        var tokensFreed = messages[firstUserIndex].tokenInfo.totalTokenCount
        messages.remove(at: firstUserIndex)
        if firstUserIndex < messages.count, messages[firstUserIndex].role == .assistant {
            tokensFreed += messages[firstUserIndex].tokenInfo.totalTokenCount
            messages.remove(at: firstUserIndex)
        }
        for index in messages.indices {
            messages[index] = messages[index].withTokenInfo(.zero).markInKVCache()
        }
        lastUpdatedAt = Date()
        return tokensFreed
    }

    mutating func updateTokenInfo(for messageId: UUID, tokenInfo: MessageTokenInfo) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        messages[index] = messages[index].withTokenInfo(tokenInfo)
        lastUpdatedAt = Date()
    }

    mutating func invalidateKVCacheState() {
        for index in messages.indices {
            messages[index].isInKVCache = false
        }
        lastUpdatedAt = Date()
    }

    func evictionPlan(tokenBudget: Int, reservedTokens: Int) -> [Int] {
        let effectiveBudget = tokenBudget - reservedTokens
        var currentTotal = totalTokenCount
        var indicesToEvict: [Int] = []
        let systemPromptIndices = Set(messages.enumerated().filter { $0.element.role == .system }.map(\.offset))
        var userMessageIndices = messages.enumerated()
            .filter { $0.element.role == .user && !systemPromptIndices.contains($0.offset) }
            .map(\.offset)

        while currentTotal > effectiveBudget, !userMessageIndices.isEmpty {
            let userIndex = userMessageIndices.removeFirst()
            indicesToEvict.append(userIndex)
            currentTotal -= messages[userIndex].tokenInfo.totalTokenCount
            let nextIndex = userIndex + 1
            if nextIndex < messages.count, messages[nextIndex].role == .assistant {
                indicesToEvict.append(nextIndex)
                currentTotal -= messages[nextIndex].tokenInfo.totalTokenCount
            }
        }
        return indicesToEvict
    }
}

// MARK: - Conversation Persistence

enum ConversationStore {
    private static let storeDirectoryName = "Conversations"

    static func storeDirectory() throws -> URL {
        let documentsDir = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let storeDir = documentsDir.appendingPathComponent(storeDirectoryName)
        if !FileManager.default.fileExists(atPath: storeDir.path) {
            try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        }
        return storeDir
    }

    static func save(_ conversation: Conversation) throws {
        let fileURL = try storeDirectory().appendingPathComponent("\(conversation.id.uuidString).json")
        let data = try JSONEncoder().encode(conversation)
        try data.write(to: fileURL, options: .atomic)
    }

    static func load(id: UUID) throws -> Conversation {
        let fileURL = try storeDirectory().appendingPathComponent("\(id.uuidString).json")
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(Conversation.self, from: data)
    }

    static func listAll() throws -> [UUID] {
        let files = try FileManager.default.contentsOfDirectory(at: try storeDirectory(), includingPropertiesForKeys: nil)
        return files.compactMap { UUID(uuidString: $0.deletingPathExtension().lastPathComponent) }
    }

    static func delete(id: UUID) throws {
        let fileURL = try storeDirectory().appendingPathComponent("\(id.uuidString).json")
        try FileManager.default.removeItem(at: fileURL)
    }
}
