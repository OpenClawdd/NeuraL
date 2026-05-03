import Foundation

enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

struct MessageTokenInfo: Codable, Sendable, Equatable {
    var promptTokenCount: Int = 0
    var generationTokenCount: Int = 0
    var totalTokenCount: Int { promptTokenCount + generationTokenCount }

    static func estimate(from text: String, role: MessageRole) -> MessageTokenInfo {
        let tokens = max(1, Int(Double(text.count) / 3.8))
        return MessageTokenInfo(
            promptTokenCount: role == .assistant ? 0 : tokens,
            generationTokenCount: role == .assistant ? tokens : 0
        )
    }
}

struct GenerationMetadata: Codable, Sendable, Equatable {
    var tokensGenerated: Int = 0
    var durationSeconds: TimeInterval = 0
    var tokensPerSecond: Double = 0
    var promptProcessingSeconds: TimeInterval = 0
    var peakMemoryBytes: UInt64 = 0
    var stopReason: String = ""

    static var placeholder: GenerationMetadata { GenerationMetadata() }
}

enum DeviceCapabilityTier: String, Codable, Sendable {
    case limited
    case standard
    case premium
    case extended
}

struct ImageAttachment: Codable, Sendable, Equatable {
    var id: UUID = UUID()
    var thumbnailData: Data = Data()
    var fullImageData: Data = Data()
    var caption: String? = nil
}

struct FunctionCallRecord: Codable, Sendable, Equatable {
    var toolName: String = ""
    var parameters: [String: String] = [:]
    var result: String = ""
}

struct RAGSourceCitation: Codable, Sendable, Equatable {
    var excerpt: String = ""
    var documentID: UUID = UUID()
    var chunkIndex: Int = 0
}

enum ArtifactKind: String, Codable, Sendable {
    case html
    case css
    case javascript
    case sandbox

    var displayName: String {
        switch self {
        case .html: return "HTML"
        case .css: return "CSS"
        case .javascript: return "JavaScript"
        case .sandbox: return "Sandbox"
        }
    }
}

struct GeneratedArtifact: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var kind: ArtifactKind
    var source: String
    var estimatedMemoryBytes: Int
    var createdAt = Date()

    var isRenderable: Bool {
        switch kind {
        case .html, .javascript, .sandbox: return true
        case .css: return false
        }
    }
}

struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
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
    var artifact: GeneratedArtifact? = nil

    static func userMessage(_ text: String) -> ChatMessage {
        ChatMessage(
            role: .user,
            content: text,
            tokenInfo: MessageTokenInfo.estimate(from: text, role: .user)
        )
    }

    static func assistantMessage(_ text: String) -> ChatMessage {
        ChatMessage(
            role: .assistant,
            content: text,
            tokenInfo: MessageTokenInfo.estimate(from: text, role: .assistant),
            artifact: GeneratedArtifact.detect(in: text)
        )
    }

    static func systemPrompt(_ text: String) -> ChatMessage {
        ChatMessage(
            role: .system,
            content: text,
            tokenInfo: MessageTokenInfo.estimate(from: text, role: .system)
        )
    }
}

extension GeneratedArtifact {
    static func detect(in text: String) -> GeneratedArtifact? {
        let fences = [
            ("```html", ArtifactKind.html),
            ("```javascript", ArtifactKind.javascript),
            ("```js", ArtifactKind.javascript),
            ("```css", ArtifactKind.css)
        ]

        for (marker, kind) in fences {
            guard let markerRange = text.range(of: marker, options: .caseInsensitive) else { continue }
            let bodyStart = markerRange.upperBound
            guard let endRange = text[bodyStart...].range(of: "```") else { continue }
            let source = String(text[bodyStart..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty else { continue }

            let title: String
            switch kind {
            case .html:
                title = "Live HTML Artifact"
            case .javascript:
                title = "Live JavaScript Artifact"
            case .css:
                title = "CSS Artifact"
            case .sandbox:
                title = "Live Sandbox"
            }

            return GeneratedArtifact(
                title: title,
                kind: kind,
                source: source,
                estimatedMemoryBytes: max(16_384, source.utf8.count * 3)
            )
        }

        if text.localizedCaseInsensitiveContains("<html")
            || text.localizedCaseInsensitiveContains("<canvas")
            || text.localizedCaseInsensitiveContains("<script") {
            return GeneratedArtifact(
                title: "Live Web Artifact",
                kind: .sandbox,
                source: text,
                estimatedMemoryBytes: max(16_384, text.utf8.count * 3)
            )
        }

        return nil
    }
}

final class Conversation: Codable, @unchecked Sendable {
    var id: UUID
    var title: String?
    var lastUpdatedAt: Date
    var messages: [ChatMessage]

    init(systemPrompt: String = "You are NeuraL, a private on-device assistant.") {
        self.id = UUID()
        self.title = nil
        self.lastUpdatedAt = Date()
        self.messages = [ChatMessage.systemPrompt(systemPrompt)]
    }

    var systemPrompt: ChatMessage? {
        messages.first { $0.role == .system }
    }

    var conversationalMessages: [ChatMessage] {
        messages.filter { $0.role != .system }
    }

    func evictOldestTurn() -> Int {
        guard let firstUser = messages.firstIndex(where: { $0.role == .user }),
              let firstAssistant = messages[firstUser...].firstIndex(where: { $0.role == .assistant }) else {
            return 0
        }

        let freed = (messages[firstUser].tokenInfo?.totalTokenCount ?? 0)
            + (messages[firstAssistant].tokenInfo?.totalTokenCount ?? 0)
        messages.remove(at: firstAssistant)
        messages.remove(at: firstUser)
        lastUpdatedAt = Date()
        return freed
    }
}
