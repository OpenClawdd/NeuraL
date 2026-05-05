import Foundation
import SwiftUI

@MainActor
final class ChatState: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isGenerating = false
    @Published var streamingText = ""
    @Published var inputText = ""
    @Published var isTracingReasoning = false
    @Published var dreamStore = DreamStore()

    @AppStorage("dream_trace_visibility") private var storedTraceVisibility = DreamStateSettings.TraceVisibility.collapsed.rawValue
    @AppStorage("dream_raw_trace_access") private var storedRawTraceAccess = false
    @AppStorage("dream_auto_create") private var storedAutoCreateDreams = true
    @AppStorage("dream_retention") private var storedRetention = DreamStateSettings.Retention.hundred.rawValue

    @Published var dreamSettings = DreamStateSettings() {
        didSet { persistDreamSettings() }
    }

    @Published var modelMetadata: ModelMetadata?

    let orchestrator = InferenceOrchestrator()
    let synthesizer = DreamSynthesizer()
    var conversation = Conversation()

    init() {
        messages = conversation.messages
        loadDreamSettings()
    }

    func sendCurrentInput() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        sendMessage(text)
    }

    func sendMessage(_ text: String) {
        let user = ChatMessage.userMessage(text)
        messages.append(user)
        conversation.messages = messages
        isGenerating = true
        streamingText = ""
        isTracingReasoning = false

        Task {
            do {
                let stream = await orchestrator.generate(promptTokens: [0], parameters: .default)
                var raw = ""
                for try await token in stream {
                    if token.isEndOfGeneration { break }
                    raw += token.text
                    let parsed = ThinkTagParser.parse(raw)
                    isTracingReasoning = parsed.isInsideThought
                    streamingText = parsed.answer
                }

                let parsed = ThinkTagParser.parse(raw)
                let assistant = ChatMessage.assistantMessage(parsed.answer, trace: parsed)
                messages.append(assistant)
                conversation.messages = messages
                streamingText = ""
                isTracingReasoning = false
                isGenerating = false

                if dreamSettings.autoCreateDreams,
                   let prompt = messages.last(where: { $0.role == .user })?.content {
                    let card = synthesizer.synthesize(
                        latestUserPrompt: prompt,
                        assistantAnswer: assistant.content,
                        reasoningTrace: assistant.reasoningTrace,
                        selectedNeuralMode: "Local",
                        pinnedMessages: [],
                        importedDocumentNames: [],
                        sourceMessageID: assistant.id
                    )
                    dreamStore.append(card, retention: dreamSettings.retention)
                }
            } catch {
                isGenerating = false
                streamingText = ""
                isTracingReasoning = false
                messages.append(.systemPrompt("Local generation failed: \(error.localizedDescription)"))
            }
        }
    }

    func useDreamAsPrompt(_ text: String) { inputText = text }
    func pinDreamMemory(_ card: DreamCard) {
        let note = card.rememberedTheme ?? card.nextAction
        messages.append(.systemPrompt("Remembered locally: \(note)"))
    }

    func applyRetention() {
        dreamStore.enforceRetention(dreamSettings.retention)
    }

    func unloadModel() { Task { await orchestrator.unloadModel() }; modelMetadata = nil }

    private func persistDreamSettings() {
        storedTraceVisibility = dreamSettings.traceVisibility.rawValue
        storedRawTraceAccess = dreamSettings.rawTraceAccess
        storedAutoCreateDreams = dreamSettings.autoCreateDreams
        storedRetention = dreamSettings.retention.rawValue
        applyRetention()
    }

    private func loadDreamSettings() {
        dreamSettings.traceVisibility = DreamStateSettings.TraceVisibility(rawValue: storedTraceVisibility) ?? .collapsed
        dreamSettings.rawTraceAccess = storedRawTraceAccess
        dreamSettings.autoCreateDreams = storedAutoCreateDreams
        dreamSettings.retention = DreamStateSettings.Retention(rawValue: storedRetention) ?? .hundred
        applyRetention()
    }
}
