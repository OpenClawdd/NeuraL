import Foundation

struct ChatMessage: Identifiable, Codable, Equatable {
    var id = UUID()
    let role: MessageRole
    var content: String
    var timestamp = Date()

    enum MessageRole: String, Codable { case user, assistant, system }

    static func userMessage(_ text: String) -> ChatMessage { ChatMessage(role: .user, content: text) }
    static func assistantMessage(_ text: String) -> ChatMessage { ChatMessage(role: .assistant, content: text) }
    static func systemPrompt(_ text: String) -> ChatMessage { ChatMessage(role: .system, content: text) }
}

class Conversation: Codable {
    var messages: [ChatMessage] = []
}
