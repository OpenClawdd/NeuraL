//
//  ChatState.swift
//  NeuraL
//
//  Phase 2 — The @Observable State Bridge
//
//  This is THE central class of Phase 2. It bridges the actor-isolated
//  InferenceOrchestrator to SwiftUI's observation system, providing:
//
//  1. Reactive state: SwiftUI views re-render when properties change
//  2. Safe actor bridging: All orchestrator calls are async; results
//     are dispatched to @MainActor for UI binding
//  3. Message management: Append user messages, stream assistant responses
//  4. Context window tracking: Know how much context is used
//  5. Generation lifecycle: Start, stream, stop, retry
//
//  ┌─────────────────────────────────────────────────────────────┐
//  │                    DATA FLOW OVERVIEW                       │
//  │                                                             │
//  │  SwiftUI View                                               │
//  │      │  ┌── reads @Observable properties ──┐                │
//  │      │  │  (engineState, messages, etc.)   │                │
//  │      │  └──────────────────────────────────┘                │
//  │      │                                                      │
//  │      ├── User action (sendMessage, stop, etc.)              │
//  │      ▼                                                      │
//  │  ChatState (@MainActor, @Observable)                        │
//  │      │                                                      │
//  │      ├── async calls ──→ InferenceOrchestrator (actor)      │
//  │      │                                                      │
//  │      ├── consumes AsyncStream<EmittedToken>                 │
//  │      │       │                                              │
//  │      │       ├── Updates streamingText (per-token)          │
//  │      │       ├── Updates contextUsed (per-token)            │
//  │      │       └── On EOG: finalizes ChatMessage              │
//  │      │                                                      │
//  │      └── publishes changes ──→ SwiftUI re-renders           │
//  └─────────────────────────────────────────────────────────────┘
//
//  IMPORTANT: This class is @MainActor isolated because @Observable
//  requires property changes to happen on the main thread for SwiftUI
//  to observe them correctly. All async calls to the orchestrator
//  are dispatched from here and results flow back via AsyncStream
//  consumption on the main actor.
//

import Foundation
import Observation
import os

// MARK: - Chat State Error

/// Errors specific to the ChatState layer.
enum ChatStateError: LocalizedError {
    case noModelLoaded
    case alreadyGenerating
    case emptyMessage
    case noSystemPrompt
    case contextEvictionFailed(detail: String)

    var errorDescription: String? {
        switch self {
        case .noModelLoaded: return "No model is loaded. Please load a model first."
        case .alreadyGenerating: return "A generation is already in progress."
        case .emptyMessage: return "Cannot send an empty message."
        case .noSystemPrompt: return "Conversation must have a system prompt."
        case .contextEvictionFailed(let detail): return "Context eviction failed: \(detail)"
        }
    }
}

// MARK: - Chat State

/// The primary state management class for the chat interface.
///
/// This class is the single source of truth for the UI layer. SwiftUI views
/// observe its properties and re-render when they change. It bridges the
/// actor-isolated InferenceOrchestrator to the main-thread-bound observation
/// system.
///
/// Usage:
/// ```swift
/// @State private var chatState = ChatState()
///
/// // In your view:
/// Button("Send") {
///     chatState.sendMessage("Hello, model!")
/// }
///
/// // Display streaming text:
/// Text(chatState.streamingText)
/// ```
@Observable
@MainActor
final class ChatState {

    // MARK: - Published State (observed by SwiftUI)

    /// The current state of the inference engine.
    var engineState: EngineState = .idle

    /// The active conversation.
    var conversation: Conversation

    /// The text currently being streamed from the model.
    /// This is updated token-by-token during generation and cleared
    /// when the message is finalized.
    var streamingText: String = ""

    /// Whether the model is in the "thinking" phase — generating has started
    /// but no tokens have appeared in streamingText yet. This covers the
    /// prompt processing latency (tokenization + llama_decode batches).
    /// The UI shows a ThinkingBubbleView during this phase.
    var isThinking: Bool {
        isGenerating && streamingText.isEmpty
    }

    /// Reasoning text extracted from <think/> blocks during streaming.
    /// Models like DeepSeek-R1 wrap their chain-of-thought in <think>...</think>.
    /// This text is separated from the main streamingText so the UI can
    /// display it in a collapsible thinking block rather than inline.
    var thinkingText: String = ""

    /// Duration of the thinking phase (prompt processing) in seconds.
    /// Tracked from when generation starts until the first non-thinking
    /// token appears. Used by the ThinkingSummaryView.
    var thinkingDurationSeconds: Double = 0

    /// Whether the model is currently generating a response.
    /// This is derived from engineState but exposed separately for
    /// convenient UI binding (e.g., showing/hiding a stop button).
    var isGenerating: Bool {
        if case .generating = engineState { return true }
        return false
    }

    /// Whether a model is loaded and ready for generation.
    var isReady: Bool {
        if case .ready = engineState { return true }
        return false
    }

    /// The number of tokens currently in the KV cache.
    var contextTokensUsed: Int = 0

    /// The maximum context window size.
    var maxContextTokens: Int = 0

    /// Context utilization as a percentage (0.0 to 1.0).
    var contextUtilization: Double {
        guard maxContextTokens > 0 else { return 0 }
        return Double(contextTokensUsed) / Double(maxContextTokens)
    }

    /// Metadata for the currently loaded model.
    var modelMetadata: ModelMetadata?

    /// The URL of the currently loaded model file, if any.
    /// Used by the Models tab to show which model is active.
    var loadedModelURL: URL?

    /// The current memory snapshot.
    var memorySnapshot: MemoryManager.MemorySnapshot?

    /// The most recent error, if any. Cleared on the next successful operation.
    var lastError: InferenceError?

    /// The last generation metrics.
    var lastGenerationMetrics: GenerationMetadata?

    /// Whether a context eviction happened recently (for UI notification).
    var lastEvictionNotice: String?

    /// The reasoning text from the last completed generation.
    /// Stored so the finalized assistant message can show a collapsible
    /// "Thought for Xs" summary.
    var lastThinkingText: String?

    // MARK: - Configuration

    /// The chat template format to use. Defaults to .llama3.
    var templateFormat: ChatTemplateFormat = .llama3

    /// The default system prompt for new conversations.
    var defaultSystemPrompt: String

    /// Generation parameters for the next generation.
    var generationParameters: GenerationParameters = .chat

    /// Context eviction strategy.
    var evictionStrategy: EvictionStrategy = .balanced

    /// Number of tokens to reserve for generation.
    var reservedGenerationTokens: Int = 512

    // MARK: - Phase 6: Multimodal & Intelligence State

    /// Image attachments for the current message being composed.
    var pendingImageAttachments: [ImageAttachment] = []

    /// Whether the vision encoder is loaded and ready.
    var isVisionReady: Bool = false

    /// Whether RAG (document Q&A) is enabled.
    var isRAGEnabled: Bool = true

    /// RAG source citations for the last response.
    var lastRAGSources: [RAGSourceCitation]?

    /// Function call records from the last generation.
    var lastFunctionCalls: [FunctionCallRecord]?

    /// Whether function calling / tool use is enabled.
    var isToolUseEnabled: Bool = true

    /// Speech manager for voice input/output.
    var speechManager = SpeechManager()

    /// Vision encoder for multimodal models.
    private var visionEncoder: VisionEncoder = VisionEncoder()

    /// RAG pipeline for document Q&A.
    private var ragPipeline: RAGPipeline = RAGPipeline()

    // MARK: - Phase 7: Personalization State

    /// Branch manager for conversation branching and message editing.
    var branchManager = BranchManager()

    /// Whether the export sheet is shown.
    var isExportSheetPresented: Bool = false

    /// Whether the reaction picker is shown for a given message ID.
    var showReactionPickerFor: UUID? = nil

    // MARK: - Internal State

    /// The inference engine orchestrator (actor).
    private let orchestrator: InferenceOrchestrator

    /// The chat template engine.
    private var templateEngine: ChatTemplateEngine

    /// The smart context evictor.
    private var contextEvictor: SmartContextEvictor

    /// Task for the current generation.
    private var generationTask: Task<Void, Never>?

    /// Task for monitoring engine state changes.
    private var stateMonitoringTask: Task<Void, Never>?

    /// Flag indicating that the KV cache has been rebuilt by the SmartContextEvictor.
    /// When true, the next generation call uses generateFromExistingContext()
    /// instead of generate() to prevent dual-processing of the prompt.
    private var isContextRebuilt: Bool = false

    /// Whether a memory pressure warning is currently active.
    /// Set by the MemoryManager's pressure handler, displayed in the UI.
    var isUnderMemoryPressure: Bool = false

    /// Partially generated text saved when generation is interrupted by memory pressure.
    /// Displayed as a draft message so the user doesn't lose work.
    var memoryPressureDraft: String?

    /// Logger.
    private let logger = Logger(subsystem: "com.neural.engine", category: "ChatState")

    // MARK: - Initialization

    init(
        orchestrator: InferenceOrchestrator = InferenceOrchestrator(),
        defaultSystemPrompt: String = "You are a helpful, respectful, and honest assistant. Always answer as helpfully as possible. If you don't know the answer, say so.",
        templateFormat: ChatTemplateFormat = .llama3
    ) {
        self.orchestrator = orchestrator
        self.defaultSystemPrompt = defaultSystemPrompt
        self.templateFormat = templateFormat
        self.templateEngine = ChatTemplateEngine(format: templateFormat)
        self.contextEvictor = SmartContextEvictor(templateEngine: templateEngine)
        self.conversation = Conversation(systemPrompt: defaultSystemPrompt)

        // Start monitoring engine state
        startStateMonitoring()

        // Register memory pressure handler for graceful shutdown
        registerMemoryPressureHandler()
    }

    deinit {
        generationTask?.cancel()
        stateMonitoringTask?.cancel()
        // Unregister memory pressure handler
        Task {
            await MemoryManager.shared.unregisterMemoryPressureHandler()
        }
    }

    // MARK: - Memory Pressure Handler

    /// Register a handler with MemoryManager to gracefully handle memory pressure.
    /// When iOS signals that memory is running low, this handler:
    /// 1. Cancels the active generation
    /// 2. Saves the partially generated text as a draft
    /// 3. Marks the app as under memory pressure (displayed in UI)
    /// 4. Clears the KV cache to free memory
    private func registerMemoryPressureHandler() {
        Task {
            await MemoryManager.shared.registerMemoryPressureHandler { [weak self] event in
                guard let self = self else { return }
                Task { @MainActor in
                    self.handleMemoryPressure(event: event)
                }
            }
        }
    }

    /// Handle a memory pressure event from the OS.
    @MainActor
    private func handleMemoryPressure(event: DispatchSource.MemoryPressureEvent) {
        logger.warning("Memory pressure event received: \(event == .critical ? "CRITICAL" : "WARNING")")

        // Mark that we're under memory pressure
        isUnderMemoryPressure = true
        Task {
            await MemoryManager.shared.setUnderMemoryPressure(true)
        }

        // If generating, save partial text as draft and stop
        if isGenerating {
            if !streamingText.isEmpty {
                memoryPressureDraft = streamingText
            }
            stopGeneration()
            logger.info("Generation stopped due to memory pressure. Partial text saved as draft.")
        }

        // Clear the KV cache to free memory (the conversation is still in memory)
        Task {
            await self.orchestrator.resetContext()
        }
    }

    // MARK: - Model Management

    /// Load a model from the given URL.
    ///
    /// This is an async operation. The engineState will transition through
    /// .loading → .ready (or .error).
    func loadModel(from url: URL, configuration: ModelLoadConfiguration = .default) {
        guard !isGenerating else { return }

        // Track the URL for the Models tab
        loadedModelURL = url

        Task { [weak self] in
            guard let self = self else { return }
            do {
                try await self.orchestrator.loadModel(from: url, configuration: configuration)
                // State will be updated by the monitoring task
            } catch let error as InferenceError {
                self.lastError = error
                self.engineState = .error(error)
            } catch {
                let inferenceError = InferenceError.backendInitializationFailed(detail: error.localizedDescription)
                self.lastError = inferenceError
                self.engineState = .error(inferenceError)
            }
        }
    }

    /// Unload the current model.
    func unloadModel() {
        guard !isGenerating else { return }
        generationTask?.cancel()
        loadedModelURL = nil

        Task { [weak self] in
            guard let self = self else { return }
            await self.orchestrator.unloadModel()
        }
    }

    // MARK: - Message Sending

    /// Send a user message and generate an assistant response.
    ///
    /// This is the primary interaction method. It:
    /// 1. Appends the user message to the conversation
    /// 2. Checks context window capacity and evicts if needed
    /// 3. Formats the prompt using the chat template
    /// 4. Starts generation
    /// 5. Streams the response token-by-token
    /// 6. Finalizes the assistant message when generation completes
    ///
    /// - Parameter content: The user's message text.
    func sendMessage(_ content: String) {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastError = InferenceError.backendInitializationFailed(detail: "Cannot send an empty message.")
            return
        }
        guard isReady else {
            lastError = InferenceError.backendInitializationFailed(detail: "No model is loaded.")
            return
        }
        guard !isGenerating else { return }

        // Append the user message
        let userMessage = ChatMessage.userMessage(content)
        conversation.append(userMessage)

        // Start generation
        startGeneration()
    }

    /// Stop the current generation.
    ///
    /// The partially generated text will be saved as a (short) assistant message.
    func stopGeneration() {
        guard isGenerating else { return }
        generationTask?.cancel()
        finalizeStreamingMessage(stopReason: .cancelled)
    }

    /// Clear the conversation and start fresh (preserves the system prompt).
    func clearConversation() {
        guard !isGenerating else { return }

        let systemPromptContent = conversation.systemPrompt?.content ?? defaultSystemPrompt
        conversation = Conversation(systemPrompt: systemPromptContent)
        streamingText = ""
        contextTokensUsed = 0
        lastError = nil
        lastEvictionNotice = nil

        // Reset the engine's context
        Task { [weak self] in
            guard let self = self else { return }
            await self.orchestrator.resetContext()
        }
    }

    /// Regenerate the last assistant response.
    ///
    /// Removes the last assistant message and re-generates from the same context.
    func regenerateLastResponse() {
        guard !isGenerating else { return }

        // Find and remove the last assistant message
        if conversation.messages.last?.role == .assistant {
            conversation.removeMessage(id: conversation.messages.last!.id)
        }

        // Start generation
        startGeneration()
    }

    // MARK: - Template Format Changes

    /// Update the chat template format.
    func setTemplateFormat(_ format: ChatTemplateFormat) {
        templateFormat = format
        templateEngine = ChatTemplateEngine(format: format)
        contextEvictor = SmartContextEvictor(templateEngine: templateEngine)
    }

    // MARK: - Phase 6: Image Attachments

    /// Add an image attachment to the current message.
    func addImageAttachment(_ attachment: ImageAttachment) {
        pendingImageAttachments.append(attachment)
    }

    /// Remove an image attachment by ID.
    func removeImageAttachment(id: UUID) {
        pendingImageAttachments.removeAll { $0.id == id }
    }

    /// Clear all pending image attachments.
    func clearImageAttachments() {
        pendingImageAttachments = []
    }

    /// Send a message with optional image attachments.
    func sendMessage(_ content: String, images: [ImageAttachment] = []) {
        let attachments = images.isEmpty ? pendingImageAttachments : images
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty else {
            lastError = InferenceError.backendInitializationFailed(detail: "Cannot send an empty message.")
            return
        }
        guard isReady else {
            lastError = InferenceError.backendInitializationFailed(detail: "No model is loaded.")
            return
        }
        guard !isGenerating else { return }

        // Append the user message with any image attachments
        let userMessage = ChatMessage.userMessage(content, imageAttachments: attachments.isEmpty ? nil : attachments)
        conversation.append(userMessage)

        // Clear pending attachments after sending
        pendingImageAttachments = []

        // Start generation
        startGeneration()
    }

    // MARK: - Phase 6: Vision Encoder Management

    /// Load a vision projector model (.mmproj).
    func loadVisionProjector(at url: URL) {
        Task {
            do {
                try await visionEncoder.loadProjector(at: url)
                isVisionReady = await visionEncoder.isReady
            } catch {
                lastError = InferenceError.backendInitializationFailed(
                    detail: "Vision projector load failed: \(error.localizedDescription)"
                )
            }
        }
    }

    /// Unload the vision projector.
    func unloadVisionProjector() {
        Task {
            await visionEncoder.unloadProjector()
            isVisionReady = false
        }
    }

    // MARK: - Phase 6: RAG

    /// Import a document for RAG.
    func importDocument(at url: URL) async throws -> ImportedDocument {
        let importer = DocumentImporter()
        return try await importer.importDocument(at: url)
    }

    /// Get all imported RAG documents.
    func ragDocuments() async -> [ImportedDocument] {
        await VectorStore.shared.allDocuments()
    }

    /// Remove a RAG document.
    func removeRAGDocument(id: UUID) async {
        await VectorStore.shared.removeDocument(id: id)
    }

    // MARK: - Phase 6: Tool Use

    /// Load built-in tools into the registry.
    func initializeTools() {
        Task {
            await BuiltInTools.registerAll()
        }
    }

    // MARK: - Phase 7: Conversation Branching

    /// Regenerate the response from a specific assistant message, creating a branch.
    /// If the message is the last assistant message, it simply regenerates without
    /// creating a new branch. Otherwise, it creates a branch for exploration.
    func regenerateFromMessage(id: UUID) {
        guard !isGenerating else { return }

        // Check if this is the last assistant message — simple case
        if conversation.messages.last?.role == .assistant && conversation.messages.last?.id == id {
            regenerateLastResponse()
            return
        }

        // For non-last messages, create a branch and regenerate
        let _ = branchManager.createBranch(divergingFrom: id)

        // Remove messages after this one and regenerate
        if let index = conversation.messages.firstIndex(where: { $0.id == id }) {
            // Remove the assistant message and everything after it
            let removeRange = index..<conversation.messages.endIndex
            conversation.messages.removeSubrange(removeRange)
        }

        startGeneration()
    }

    /// Edit a user message and regenerate the response.
    func editUserMessage(id: UUID, newContent: String) {
        guard !isGenerating else { return }
        guard let index = conversation.messages.firstIndex(where: { $0.id == id }) else { return }

        // Store the edit in the branch manager
        branchManager.editMessage(id: id, newContent: newContent)

        // Update the message content
        let original = conversation.messages[index]
        conversation.messages[index] = ChatMessage.userMessage(newContent, imageAttachments: original.imageAttachments)

        // Remove all messages after this one (responses that followed)
        let removeRange = (index + 1)..<conversation.messages.endIndex
        if !removeRange.isEmpty {
            conversation.messages.removeSubrange(removeRange)
        }

        // Reset the engine's context and regenerate
        Task { [weak self] in
            guard let self = self else { return }
            await self.orchestrator.resetContext()
        }

        startGeneration()
    }

    /// Add an emoji reaction to a message.
    func addReaction(emoji: String, to messageId: UUID) {
        branchManager.addReaction(emoji: emoji, to: messageId)
    }

    /// Show the export sheet for the current conversation.
    func showExportSheet() {
        isExportSheetPresented = true
    }

    /// Archive the current conversation and start a fresh one.
    func archiveCurrentConversation() {
        let conv = conversation
        let hasMessages = conv.messages.contains { $0.role != .system }
        if hasMessages {
            try? ConversationStore.save(conv)
            try? ConversationArchive.archive(conversationId: conv.id)
        }
        conversation = Conversation(systemPrompt: conversation.systemPrompt?.content ?? defaultSystemPrompt)
        contextTokensUsed = 0
        branchManager.reset()
        Task { [weak self] in
            guard let self = self else { return }
            await self.orchestrator.resetContext()
        }
    }

    // MARK: - Private: Generation Lifecycle

    /// Start a generation cycle for the current conversation state.
    ///
    /// This method handles two distinct flows:
    /// 1. **Normal flow**: Format the prompt, call generate() which tokenizes + processes + generates
    /// 2. **Post-eviction flow**: The KV cache was already rebuilt by the evictor, so we call
    ///    generateFromExistingContext() which skips tokenization and prompt processing
    private func startGeneration() {
        guard isReady else { return }

        // Clear any previous error
        lastError = nil
        lastEvictionNotice = nil

        // Create the generation task
        generationTask = Task { [weak self] in
            guard let self = self else { return }

            do {
                // ── Step 0: RAG augmentation (Phase 6.3) ───────────────
                var ragResult: RAGResult?
                if self.isRAGEnabled {
                    let lastUserMessage = self.conversation.messages.last(where: { $0.role == .user })?.content ?? ""
                    let shouldUseRAG = await self.ragPipeline.shouldUseRAG(for: lastUserMessage)
                    if shouldUseRAG {
                        ragResult = await self.ragPipeline.retrieve(for: lastUserMessage)
                        if let result = ragResult, result.hasContext {
                            self.logger.info("RAG: Retrieved \(result.retrievedChunks.count) chunks, \(result.contextTokensUsed) tokens from \(result.sourceSummary)")
                        }
                    }
                }

                // ── Step 1: Check context capacity ─────────────────────
                let maxCtx = await self.orchestrator.maxContextLength
                let needsEviction = await self.contextEvictor.needsEviction(
                    conversation: self.conversation,
                    maxContextTokens: maxCtx,
                    reservedForGeneration: self.reservedGenerationTokens
                )

                if needsEviction {
                    // ── Step 1a: Perform eviction ──────────────────────
                    let evictionResult = await self.contextEvictor.evictIfNeeded(
                        conversation: self.conversation,
                        maxContextTokens: maxCtx,
                        reservedForGeneration: self.reservedGenerationTokens,
                        strategy: self.evictionStrategy
                    )

                    if let result = evictionResult {
                        self.conversation = result.remainingConversation
                        self.lastEvictionNotice = result.description
                        self.logger.info("Context eviction: \(result.description)")

                        // ── Step 1b: Reset engine context and re-process ─
                        await self.orchestrator.resetContext()

                        // Re-process the reformatted prompt
                        let promptTokens = await self.orchestrator.tokenizeForEviction(
                            text: result.reformattedPrompt,
                            addBOS: true,
                            special: true
                        )
                        if !promptTokens.isEmpty {
                            try await self.orchestrator.processPromptAfterEviction(tokens: promptTokens)
                        }

                        self.isContextRebuilt = true
                    }
                }

                // ── Step 2: Start generation ───────────────────────────
                let stream: AsyncStream<EmittedToken>

                if self.isContextRebuilt {
                    let assistantHeader = self.templateEngine.assistantHeaderForFormat
                    let headerTokens = await self.orchestrator.tokenizeForEviction(
                        text: assistantHeader,
                        addBOS: false,
                        special: true
                    )

                    stream = try await self.orchestrator.generateFromExistingContext(
                        assistantHeaderTokens: headerTokens,
                        parameters: self.generationParameters
                    )

                    self.isContextRebuilt = false
                    self.logger.info("Using generateFromExistingContext (post-eviction path)")
                } else {
                    // Build the prompt, optionally augmented with RAG context
                    var systemPromptContent = self.conversation.systemPrompt?.content ?? self.defaultSystemPrompt

                    // Augment system prompt with RAG context if available
                    if let ragResult = ragResult, ragResult.hasContext {
                        systemPromptContent += "\n\n" + ragResult.augmentedSystemPrompt
                    }

                    // Augment with tool definitions if enabled (Phase 6.2)
                    if self.isToolUseEnabled {
                        let toolDefs = await ToolRegistry.shared.generateToolDefinitionsPrompt()
                        if !toolDefs.isEmpty {
                            systemPromptContent += "\n\n" + toolDefs
                        }
                    }

                    // Create a conversation with the augmented system prompt
                    var augmentedConversation = self.conversation
                    if let sysIdx = augmentedConversation.messages.firstIndex(where: { $0.role == .system }) {
                        // Replace the system prompt with the augmented version
                        let originalSystem = augmentedConversation.messages[sysIdx]
                        augmentedConversation.messages[sysIdx] = ChatMessage.systemPrompt(systemPromptContent)
                    }

                    let prompt = self.templateEngine.formatPrompt(
                        conversation: augmentedConversation,
                        forGeneration: true
                    )

                    stream = try await self.orchestrator.generate(
                        prompt: prompt,
                        parameters: self.generationParameters
                    )
                    self.logger.info("Using generate (normal path)")
                }

                // ── Step 3: Consume the token stream ───────────────────
                self.engineState = .generating
                var generatedTokenCount = 0
                let generationStartTime = ContinuousClock.now
                let thinkingStartTime = ContinuousClock.now

                // Track <think/> blocks for reasoning separation
                var isInThinkingBlock = false
                var accumulatedRaw = ""  // Full raw text including think tags
                var thinkingBuffer = ""  // Text inside <think/> blocks
                var responseBuffer = ""  // Text outside <think/> blocks

                for await token in stream {
                    if Task.isCancelled { break }

                    accumulatedRaw += token.text
                    generatedTokenCount = token.cumulativeTokenCount
                    self.contextTokensUsed = await self.orchestrator.activeContextLength

                    // ── <think/> block detection ───────────────────────
                    if accumulatedRaw.hasPrefix("<think") && !accumulatedRaw.contains("</think") {
                        isInThinkingBlock = true
                        if let tagEnd = accumulatedRaw.range(of: ">") {
                            thinkingBuffer = String(accumulatedRaw[tagEnd.upperBound...])
                        }
                    } else if isInThinkingBlock && accumulatedRaw.contains("</think") {
                        if let closeTag = accumulatedRaw.range(of: "</think", options: .backwards) {
                            thinkingBuffer = String(accumulatedRaw[accumulatedRaw.startIndex..<closeTag.lowerBound])
                            if let openEnd = thinkingBuffer.range(of: ">\n") ?? thinkingBuffer.range(of: ">") {
                                thinkingBuffer = String(thinkingBuffer[openEnd.upperBound...])
                            }
                            if let afterClose = accumulatedRaw.range(of: ">\n", range: closeTag.lowerBound..<accumulatedRaw.endIndex) {
                                responseBuffer = String(accumulatedRaw[afterClose.upperBound...])
                            }
                        }
                        isInThinkingBlock = false
                    } else if isInThinkingBlock {
                        if let tagEnd = accumulatedRaw.range(of: ">\n") ?? accumulatedRaw.range(of: ">") {
                            thinkingBuffer = String(accumulatedRaw[tagEnd.upperBound...])
                        }
                    } else {
                        responseBuffer = accumulatedRaw
                    }

                    self.thinkingText = thinkingBuffer
                    self.streamingText = responseBuffer
                    if thinkingBuffer.isEmpty && responseBuffer.isEmpty {
                        let thinkingElapsed = ContinuousClock.now - thinkingStartTime
                        self.thinkingDurationSeconds = Double(thinkingElapsed.components.seconds) +
                            Double(thinkingElapsed.components.attoseconds) / 1_000_000_000_000_000_000
                    }
                }

                // ── Step 3b: Function call detection (Phase 6.2) ───────
                let functionCalls = FunctionCallParser.parseCalls(from: accumulatedRaw)
                var functionCallRecords: [FunctionCallRecord] = []

                if !functionCalls.isEmpty && self.isToolUseEnabled {
                    self.logger.info("Detected \(functionCalls.count) function call(s) in response")

                    let executor = ToolExecutor()
                    for call in functionCalls {
                        let startTime = ContinuousClock.now
                        let result = await executor.execute(call: call)
                        let elapsed = ContinuousClock.now - startTime
                        let elapsedSec = Double(elapsed.components.seconds) +
                            Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000

                        let record = FunctionCallRecord(
                            id: UUID(),
                            toolName: call.name,
                            parameters: call.parametersJSON,
                            result: result.output,
                            isSuccess: result.isSuccess,
                            durationSeconds: elapsedSec
                        )
                        functionCallRecords.append(record)
                        self.logger.info("Tool '\(call.name)' executed: \(result.isSuccess ? "success" : "failure") in \(String(format: "%.2f", elapsedSec))s")
                    }

                    self.lastFunctionCalls = functionCallRecords
                }

                // ── Step 3c: RAG citation extraction (Phase 6.3) ───────
                if let ragResult = ragResult, ragResult.hasContext {
                    var citations: [RAGSourceCitation] = []
                    for result in ragResult.retrievedChunks {
                        citations.append(RAGSourceCitation(
                            id: UUID(),
                            documentName: result.chunk.documentName,
                            chunkIndex: result.chunk.chunkIndex,
                            similarity: result.similarity,
                            snippet: String(result.chunk.text.prefix(100))
                        ))
                    }
                    self.lastRAGSources = citations
                }

                // ── Step 4: Finalize the message ───────────────────────
                let elapsed = ContinuousClock.now - generationStartTime
                let elapsedSeconds = Double(elapsed.components.seconds) +
                                    Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000

                let stopReason: GenerationMetadata.StopReason = Task.isCancelled ? .cancelled : .endOfGenerationToken

                // Strip function call blocks from the display text
                let displayText = FunctionCallParser.stripFunctionCalls(from: self.streamingText.isEmpty ? accumulatedRaw : self.streamingText)
                if !displayText.isEmpty {
                    self.streamingText = displayText
                }

                self.finalizeStreamingMessage(
                    stopReason: stopReason,
                    tokensGenerated: generatedTokenCount,
                    durationSeconds: elapsedSeconds,
                    functionCalls: functionCallRecords.isEmpty ? nil : functionCallRecords,
                    ragSources: self.lastRAGSources
                )

                self.contextTokensUsed = await self.orchestrator.activeContextLength
                self.maxContextTokens = await self.orchestrator.maxContextLength
                self.engineState = await self.orchestrator.state

            } catch let error as InferenceError {
                self.lastError = error
                self.engineState = .error(error)
                self.streamingText = ""
                self.isContextRebuilt = false
            } catch {
                let inferenceError = InferenceError.backendInitializationFailed(detail: error.localizedDescription)
                self.lastError = inferenceError
                self.engineState = .error(inferenceError)
                self.streamingText = ""
                self.isContextRebuilt = false
            }
        }
    }

    /// Finalize the streaming text into a ChatMessage and append it.
    private func finalizeStreamingMessage(
        stopReason: GenerationMetadata.StopReason = .endOfGenerationToken,
        tokensGenerated: Int = 0,
        durationSeconds: Double = 0,
        functionCalls: [FunctionCallRecord]? = nil,
        ragSources: [RAGSourceCitation]? = nil
    ) {
        guard !streamingText.isEmpty else {
            // If no tokens were generated, don't create an empty message
            streamingText = ""
            return
        }

        let metadata = GenerationMetadata(
            tokensGenerated: tokensGenerated,
            durationSeconds: durationSeconds,
            promptProcessingSeconds: 0,
            peakMemoryBytes: 0,
            stopReason: stopReason
        )

        let tokenInfo = MessageTokenInfo(
            promptTokenCount: 0,
            generationTokenCount: tokensGenerated
        )

        let assistantMessage = ChatMessage.assistantMessage(
            streamingText,
            tokenInfo: tokenInfo,
            metadata: metadata,
            thinkingText: thinkingText.isEmpty ? nil : thinkingText,
            thinkingDurationSeconds: thinkingDurationSeconds,
            functionCalls: functionCalls,
            ragSources: ragSources
        )

        conversation.append(assistantMessage)
        lastGenerationMetrics = metadata

        if !thinkingText.isEmpty {
            lastThinkingText = thinkingText
        } else {
            lastThinkingText = nil
        }

        // Auto-read response if enabled (Phase 6.4)
        if speechManager.isAutoReadEnabled {
            speechManager.speak(streamingText)
        }

        streamingText = ""
        thinkingText = ""

        logger.info("Message finalized: \(tokensGenerated) tokens in \(String(format: "%.2f", durationSeconds))s (\(String(format: "%.1f", metadata.tokensPerSecond)) tok/s), stop=\(stopReason)")
    }

    // MARK: - Private: State Monitoring

    /// Start a background task that periodically syncs the orchestrator's
    /// state to this @Observable class.
    ///
    /// This is the "pull" side of the bridge. The "push" side is handled
    /// by the AsyncStream token consumption in startGeneration().
    private func startStateMonitoring() {
        stateMonitoringTask = Task { [weak self] in
            guard let self = self else { return }

            while !Task.isCancelled {
                // Sync engine state
                let state = await self.orchestrator.state
                if state != self.engineState {
                    self.engineState = state
                }

                // Sync metadata
                let metadata = await self.orchestrator.loadedModelMetadata
                if metadata?.architecture != self.modelMetadata?.architecture ||
                   metadata?.fileSize != self.modelMetadata?.fileSize {
                    self.modelMetadata = metadata
                }

                // Sync context info
                let activeCtx = await self.orchestrator.activeContextLength
                let maxCtx = await self.orchestrator.maxContextLength
                if activeCtx != self.contextTokensUsed {
                    self.contextTokensUsed = activeCtx
                }
                if maxCtx != self.maxContextTokens {
                    self.maxContextTokens = maxCtx
                }

                // Sync memory snapshot
                let snapshot = await MemoryManager.shared.snapshot()
                self.memorySnapshot = snapshot

                // Poll every 500ms while not generating (when generating,
                // the token stream provides real-time updates)
                if !self.isGenerating {
                    try? await Task.sleep(for: .milliseconds(500))
                } else {
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
        }
    }
}
