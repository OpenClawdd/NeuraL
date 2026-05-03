import SwiftUI

@MainActor
class ChatState: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isGenerating = false
    @Published var streamingText = ""
    let orchestrator = InferenceOrchestrator()
    var conversation = Conversation()

    func sendMessage(_ text: String) {
        let userMsg = ChatMessage.userMessage(text)
        messages.append(userMsg)
        isGenerating = true
        streamingText = ""

        Task {
            let tokens = await orchestrator.generate(promptTokens: [0], parameters: .default)
            var response = ""
            for token in tokens {
                response += token.text
                await MainActor.run {
                    self.streamingText = response
                }
            }
            await MainActor.run {
                self.messages.append(ChatMessage.assistantMessage(response))
                self.streamingText = ""
                self.isGenerating = false
            }
        }
    }

    var modelMetadata: ModelMetadata? { nil }
    var engineState: String { "idle" }
    var contextTokensUsed: Int { 0 }
    func ragDocuments() async -> [UUID] { [] }
    func importDocument(at url: URL) async throws {}
    func removeRAGDocument(id: UUID) async {}
    func setSystemPrompt(_ prompt: String) {
        conversation.messages[0] = ChatMessage.systemPrompt(prompt)
    }
}

