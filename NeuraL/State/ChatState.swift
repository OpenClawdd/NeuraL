import SwiftUI

@MainActor
class ChatState: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isGenerating = false
    @Published var engineState = "idle"
    let orchestrator = InferenceOrchestrator()
    var conversation = Conversation()

    func sendMessage(_ text: String) {
        let userMsg = ChatMessage.userMesimport Foundation
actor MemoryMana(userMsg)
        isGenerating = true
        Task {
            let stream = try! await orchestrator.generate(promptTokens: [0], parameters: .default)
            var response = ""
            for try await token in stream {
                response += token.text
            }
            messages.append(ChatMessage.assistantMessage(response))
            isGenerating = false
        }
    }

    func setSystemPrompt(_ prompt: String) {
        conversation.messages[0] = ChatMessage.systemPrompt(prompt)
    }
}
