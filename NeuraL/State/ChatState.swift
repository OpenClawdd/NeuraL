import SwiftUI

@MainActor
class ChatState: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isGenerating = false
    @Published var streamingTokens: [String] = []
    let orchestrator = InferenceOrchestrator()
    var conversation = Conversation()

    private var displayTimer: Timer?

    func sendMessage(_ text: String) {
        let userMsg = ChatMessage.userMessage(text)
        messages.append(userMsg)
        isGenerating = true
        streamingTokens = []

        Task {
            let tokens = await orchestrator.generate(promptTokens: [0], parameters: .default)
            await MainActor.run {
                self.streamingTokens = tokens.map { $0.text }
                self.startTokenDisplay()
            }
        }
    }

    private func startTokenDisplay() {
        var index = 0
        displayTimer?.invalidate()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self = self, index < self.streamingTokens.count else {
                timer.invalidate()
                DispatchQueue.main.async {
                    if let self = self {
                        self.messages.append(ChatMessage.assistantMessage(self.streamingTokens.joined()))
                        self.streamingTokens = []
                        self.isGenerating = false
                    }
                }
                return
            }
            index += 1
        }
    }

    func setSystemPrompt(_ prompt: String) {
        conversation.messages[0] = ChatMessage.systemPrompt(prompt)
    }
}
