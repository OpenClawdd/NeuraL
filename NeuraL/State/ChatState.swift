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
    @Published var contextTokensUsed = 0
    @Published var modelMetadata: ModelMetadata?
    @Published var loadedModelURL: URL?
    @Published var lastError: InferenceError?

    @AppStorage("dream_trace_visibility") private var storedTraceVisibility = DreamStateSettings.TraceVisibility.collapsed.rawValue
    @AppStorage("dream_raw_trace_access") private var storedRawTraceAccess = false
    @AppStorage("dream_auto_create") private var storedAutoCreateDreams = true
    @AppStorage("dream_retention") private var storedRetention = DreamStateSettings.Retention.hundred.rawValue

    @Published var dreamSettings = DreamStateSettings() {
        didSet { persistDreamSettings() }
    }

    @Published var conversation: Conversation {
        didSet { messages = conversation.messages }
    }

    let orchestrator = InferenceOrchestrator()
    let synthesizer = DreamSynthesizer()
    var defaultSystemPrompt: String
    var generationParameters: GenerationParameters = .default
    private var templateEngine = ChatTemplateEngine(format: .llama3)

    init(defaultSystemPrompt: String = "You are a helpful, respectful, and honest assistant. Always answer as helpfully as possible. If you don't know the answer, say so.") {
        self.defaultSystemPrompt = defaultSystemPrompt
        self.conversation = Conversation(systemPrompt: defaultSystemPrompt)
        self.messages = conversation.messages
        loadDreamSettings()
    }

    func loadModel(from url: URL, configuration: ModelLoadConfiguration = .default) {
        Task {
            do {
                try await orchestrator.loadModel(from: url, configuration: configuration)
                modelMetadata = await orchestrator.loadedModelMetadata
                loadedModelURL = url
                lastError = nil
            } catch let error as InferenceError {
                lastError = error
            } catch {
                lastError = .backendInitializationFailed(detail: error.localizedDescription)
            }
        }
    }

    func sendCurrentInput() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        sendMessage(text)
    }

    func sendMessage(_ text: String) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }
        guard modelMetadata != nil else {
            appendVisibleSystemMessage("No local model is loaded. Import or load a GGUF model to generate locally.")
            return
        }
        guard !isGenerating else { return }

        let user = ChatMessage.userMessage(cleanText)
        conversation.append(user)
        messages = conversation.messages
        isGenerating = true
        streamingText = ""
        isTracingReasoning = false

        Task {
            do {
                let prompt = templateEngine.formatPrompt(conversation: conversation, forGeneration: true)
                let promptTokens = try await orchestrator.tokenize(text: prompt, addBOS: true, special: true)
                let stream = await orchestrator.generate(promptTokens: promptTokens, parameters: generationParameters)
                var raw = ""
                var generatedCount = 0
                let startedAt = Date()

                for try await token in stream {
                    if token.isEndOfGeneration { break }
                    raw += token.text
                    generatedCount = token.cumulativeTokenCount
                    let parsed = ThinkTagParser.parse(raw)
                    isTracingReasoning = parsed.isInsideThought
                    streamingText = parsed.answer
                }

                let parsed = ThinkTagParser.parse(raw)
                let elapsed = Date().timeIntervalSince(startedAt)
                let metadata = GenerationMetadata(
                    tokensGenerated: generatedCount,
                    durationSeconds: elapsed,
                    promptProcessingSeconds: 0,
                    peakMemoryBytes: 0,
                    stopReason: .endOfGenerationToken
                )
                let assistant = ChatMessage.assistantMessage(
                    parsed.answer,
                    tokenInfo: MessageTokenInfo(promptTokenCount: 0, generationTokenCount: generatedCount),
                    metadata: metadata,
                    trace: parsed
                )

                if !assistant.content.isEmpty {
                    conversation.append(assistant)
                    messages = conversation.messages
                    if dreamSettings.autoCreateDreams {
                        createDreamCard(prompt: cleanText, assistant: assistant)
                    }
                }

                streamingText = ""
                isTracingReasoning = false
                isGenerating = false
                contextTokensUsed += generatedCount
            } catch let error as InferenceError {
                finishGenerationWithError(error)
            } catch {
                finishGenerationWithError(.backendInitializationFailed(detail: error.localizedDescription))
            }
        }
    }

    func setSystemPrompt(_ prompt: String) {
        defaultSystemPrompt = prompt
        conversation.setSystemPrompt(prompt)
        messages = conversation.messages
    }

    func useDreamAsPrompt(_ text: String) { inputText = text }

    func pinDreamMemory(_ card: DreamCard) {
        let note = card.rememberedTheme ?? card.nextAction
        appendVisibleSystemMessage("Remembered locally: \(note)")
    }

    func applyRetention() {
        dreamStore.enforceRetention(dreamSettings.retention)
    }

    func unloadModel() {
        Task { await orchestrator.unloadModel() }
        modelMetadata = nil
        loadedModelURL = nil
        contextTokensUsed = 0
    }

    private func createDreamCard(prompt: String, assistant: ChatMessage) {
        let card = synthesizer.synthesize(
            latestUserPrompt: prompt,
            assistantAnswer: assistant.content,
            reasoningTrace: assistant.reasoningTrace,
            selectedNeuralMode: "Local",
            pinnedMessages: conversation.messages.filter { $0.role == .system }.map(\.content),
            importedDocumentNames: [],
            sourceMessageID: assistant.id
        )
        dreamStore.append(card, retention: dreamSettings.retention)
    }

    private func appendVisibleSystemMessage(_ text: String) {
        conversation.append(.systemPrompt(text))
        messages = conversation.messages
    }

    private func finishGenerationWithError(_ error: InferenceError) {
        lastError = error
        isGenerating = false
        streamingText = ""
        isTracingReasoning = false
        appendVisibleSystemMessage("Local generation failed: \(error.localizedDescription)")
    }

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
