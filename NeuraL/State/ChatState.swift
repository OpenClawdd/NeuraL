import SwiftUI

@MainActor
class ChatState: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isGenerating = false
    let orchestrator = InferenceOrchestrator()
    var conversation = Conversation()

    func sendMessage(_ text: String) {
        let userMsg = ChatMessage.userMessage(text)
        messages.append(userMsg)
        isGenerating = true
        Task {
            let stream = orchestrator.generate(promptTokens: [0], parameters: .default)
            var response = ""
            for await token in stream {
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
