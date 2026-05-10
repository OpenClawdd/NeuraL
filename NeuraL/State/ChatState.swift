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
    @AppStorage("has_completed_onboarding") var hasCompletedOnboarding: Bool = false
    @AppStorage("imported_model_path") var importedModelPath: String = ""

    @Published var engineState: EngineState = .idle

    @Published var dreamSettings = DreamStateSettings() {
        didSet { persistDreamSettings() }
    }

    @Published var modelMetadata: ModelMetadata?
    @Published var contextTokensUsed: Int = 0
    @Published var importedDocuments: [ImportedDocument] = []
    @Published var swarmSnapshot = SwarmSnapshot()
    @Published var shadowInsights: [ShadowInsight] = []
    @Published var pinnedVisibleMessages: [ChatMessage] = []

    let orchestrator = InferenceOrchestrator()
    let synthesizer = DreamSynthesizer()
    let documentImporter = DocumentImporter()
    var conversation = Conversation()

    let defaultSystemPrompt = "You are a helpful assistant."

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
                let promptTokens = try await orchestrator.tokenize(text: text)
                
                // Smoke test parameters
                let params = GenerationParameters(
                    maxTokens: 128,
                    temperature: 0.7,
                    topP: 0.9,
                    topK: 40,
                    repeatPenalty: 1.1,
                    repeatPenaltyWindowSize: 64,
                    stopTokens: ["</s>", "<|end|>", "<|im_end|>", "<|eot_id|>"],
                    seed: nil
                )
                
                let stream = await orchestrator.generate(promptTokens: promptTokens, parameters: params)
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
                   let prompt = messages.last(where: { $0.role == .user })?.content,
                   let card = synthesizer.synthesize(
                        latestUserPrompt: prompt,
                        assistantAnswer: assistant.content,
                        reasoningTrace: assistant.reasoningTrace,
                        selectedNeuralMode: "Local",
                        pinnedMessages: [],
                        importedDocumentNames: [],
                        sourceMessageID: assistant.id
                   ) {
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

    func setSystemPrompt(_ content: String) {
        if let index = conversation.messages.firstIndex(where: { $0.role == .system }) {
            conversation.messages[index].content = content
        } else {
            conversation.messages.insert(.systemPrompt(content), at: 0)
        }
        messages = conversation.messages
    }

    func unloadModel() { Task { await orchestrator.unloadModel() }; modelMetadata = nil }

    func importModel(from url: URL) {
        Task {
            do {
                let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let destURL = docsURL.appendingPathComponent(url.lastPathComponent)
                
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                
                _ = url.startAccessingSecurityScopedResource()
                defer { url.stopAccessingSecurityScopedResource() }
                
                try FileManager.default.copyItem(at: url, to: destURL)
                
                importedModelPath = destURL.lastPathComponent
                messages.append(.systemPrompt("Model imported: \(destURL.lastPathComponent). Ready to load."))
            } catch {
                messages.append(.systemPrompt("Model import failed: \(error.localizedDescription)"))
            }
        }
    }

    func loadModel() {
        guard !importedModelPath.isEmpty else { return }
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let modelURL = docsURL.appendingPathComponent(importedModelPath)
        
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            engineState = .error(InferenceError.modelNotFound(path: modelURL.path))
            return
        }

        Task {
            engineState = .loading(progress: 0.0)
            do {
                try await orchestrator.loadModel(path: modelURL.path, config: .default)
                modelMetadata = await orchestrator.loadedModelMetadata
                engineState = .ready
            } catch {
                engineState = .error(error as? InferenceError ?? InferenceError.backendInitializationFailed(detail: error.localizedDescription))
                messages.append(.systemPrompt("Model load failed: \(error.localizedDescription)"))
            }
        }
    }

    func importDocument(from url: URL) {
        Task {
            do {
                let doc = try await documentImporter.importDocument(at: url)
                importedDocuments.append(doc)
            } catch {
                messages.append(.systemPrompt("Document import failed: \(error.localizedDescription)"))
            }
        }
    }

    func runShadowSynthesis() {
        // Placeholder: shadow synthesis runs via background task.
        // Will scan recent dreams and conversation context for proactive insights.
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

// MARK: - NeuralLab stub types (wired when features land)

struct SwarmSnapshot: Equatable {
    enum State: String, Equatable { case idle = "Idle" }
    struct Local: Equatable { var tokensPerSecond: Double = 0 }
    struct Remote: Equatable { var modelName: String = ""; var tokensPerSecond: Double = 0 }

    var state: State = .idle
    var local: Local = Local()
    var consensusScore: Double = 0
    var remote: Remote? = nil
    var critique: String = "Local-only mode active. Swarm features require configured remotes."
}

struct ShadowInsight: Identifiable, Equatable {
    let id = UUID()
    var title: String = ""
    var summary: String = ""
    var confidence: Double = 0
}
