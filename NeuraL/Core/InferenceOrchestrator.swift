//
//  InferenceOrchestrator.swift
//  NeuraL
//
//  Phase 1 — Main Engine Class
//
//  The InferenceOrchestrator is the public-facing implementation of the
//  InferenceEngine protocol. It coordinates:
//
//  - LlamaCppBridge: Low-level llama.cpp interaction
//  - MemoryManager: Budgeting and thermal monitoring
//  - ModelLoader: Validation and loading orchestration
//  - TokenStreamController: UTF-8-safe token streaming
//
//  This is the ONLY class that the rest of the application (Phase 2's
//  state manager, Phase 3's UI) will interact with. All implementation
//  details of llama.cpp, memory probing, and token accumulation are
//  hidden behind the InferenceEngine protocol.
//
//  Architecture decision: InferenceOrchestrator is an actor because:
//  1. It owns mutable state (engine state, metadata, bridge reference)
//  2. It must serialize access to the bridge (which is also an actor)
//  3. It prevents the UI from calling generate() while already generating
//  4. It ensures unloadModel() safely cancels active generation
//
//  Rumination on actor isolation and @Observable:
//  In Phase 2, we'll need the state to be observable by SwiftUI. Actors
//  can't directly conform to ObservableObject (which requires main-actor
//  isolation). The solution: InferenceOrchestrator will be the "engine"
//  layer, and a separate @Observable / ObservableObject wrapper in Phase 2
//  will bridge the actor's state to the main thread. This keeps the engine
//  testable and the UI reactive without compromising thread safety.
//

import Foundation
import os

// MARK: - InferenceOrchestrator

/// The main inference engine implementation. Conforms to the InferenceEngine
/// protocol and coordinates all subsystems.
actor InferenceOrchestrator: InferenceEngine {

    // MARK: - Dependencies

    private let bridge: LlamaCppBridge
    private let modelLoader: ModelLoader
    private let memoryManager: MemoryManager

    // MARK: - State

    /// The current engine state. Updated atomically within the actor.
    private var _state: EngineState = .idle

    /// Metadata for the currently loaded model.
    private var _loadedModelMetadata: ModelMetadata?

    /// The loading configuration used for the current model.
    private var _loadConfiguration: ModelLoadConfiguration?

    /// The token stream controller for the current generation.
    private var streamController: TokenStreamController?

    /// Logger for structured diagnostics.
    private let logger = Logger(subsystem: "com.neural.engine", category: "Orchestrator")

    // MARK: - Initialization

    /// Create a new InferenceOrchestrator with default dependencies.
    ///
    /// In production, use the static `shared` singleton. In tests,
    /// create instances with mock dependencies.
    init(
        bridge: LlamaCppBridge = LlamaCppBridge(),
        modelLoader: ModelLoader = ModelLoader(),
        memoryManager: MemoryManager = .shared
    ) {
        self.bridge = bridge
        self.modelLoader = modelLoader
        self.memoryManager = memoryManager
        logger.info("InferenceOrchestrator initialized.")
    }

    // MARK: - InferenceEngine Conformance

    var state: EngineState {
        _state
    }

    var loadedModelMetadata: ModelMetadata? {
        _loadedModelMetadata
    }

    var activeContextLength: Int {
        get async {
            await bridge.contextLength
        }
    }

    var maxContextLength: Int {
        get async {
            await bridge.maxContextLength
        }
    }

    // MARK: - Model Loading

    func loadModel(from modelURL: URL, configuration: ModelLoadConfiguration) async throws {
        // Guard: only load from idle state
        guard _state == .idle else {
            throw InferenceError.backendInitializationFailed(
                detail: "Cannot load model while in \(_state) state. Unload first."
            )
        }

        // Guard: must not be on the main thread
        assert(!Thread.isMainThread, "loadModel must not be called on the main thread")

        // Update state to loading
        updateState(.loading(progress: 0.0))
        logger.info("Loading model from: \(modelURL.path)")

        do {
            // Use the ModelLoader to validate, budget, and load
            let result = try await modelLoader.load(
                modelURL: modelURL,
                configuration: configuration,
                into: bridge
            )

            // Update our state with the loaded model's metadata
            _loadedModelMetadata = result.metadata
            _loadConfiguration = configuration

            updateState(.ready)

            logger.info("""
                Model loaded successfully:
                  Architecture: \(result.metadata.architecture)
                  Layers: \(result.metadata.layerCount)
                  Embedding dim: \(result.metadata.embeddingDimension)
                  Context: \(result.configuration.contextLength) tokens
                  GPU layers: \(result.configuration.gpuLayerCount)
                  Memory budget: \(formatBytes(result.budget.estimatedTotalBytes))
                  Thermal state: \(result.budget.thermalState)
                """)

            // Log memory snapshot for diagnostics
            let snapshot = await memoryManager.snapshot()
            logger.info("Post-load memory: \(snapshot.description)")

        } catch let error as InferenceError {
            updateState(.error(error))
            logger.error("Model loading failed: \(error)")
            throw error
        } catch {
            let inferenceError = InferenceError.backendInitializationFailed(detail: error.localizedDescription)
            updateState(.error(inferenceError))
            logger.error("Model loading failed: \(error)")
            throw inferenceError
        }
    }

    // MARK: - Model Unloading

    func unloadModel() async {
        guard _state != .idle else { return }

        updateState(.unloading)
        logger.info("Unloading model...")

        // Cancel any active generation
        streamController?.cancelGeneration()
        streamController = nil

        // Release all bridge resources
        await bridge.unloadModel()

        _loadedModelMetadata = nil
        _loadConfiguration = nil

        updateState(.idle)
        logger.info("Model unloaded. Engine idle.")
    }

    // MARK: - Generation

    func generate(
        prompt: String,
        parameters: GenerationParameters
    ) async throws -> AsyncStream<EmittedToken> {
        // Guard: must be in ready state
        guard _state == .ready else {
            throw InferenceError.backendInitializationFailed(
                detail: "Cannot generate while in \(_state) state. Load a model first."
            )
        }

        // Guard: must not be on the main thread
        assert(!Thread.isMainThread, "generate must not be called on the main thread")

        updateState(.generating)
        logger.info("Starting generation. Prompt length: \(prompt.count) chars, max tokens: \(parameters.maxTokens)")

        // ── Step 1: Tokenize the prompt ────────────────────────────────
        let promptTokens = await bridge.tokenize(
            text: prompt,
            addBOS: true,   // Always add BOS for a new prompt
            special: false   // Don't parse special tokens in user input
        )

        guard !promptTokens.isEmpty else {
            updateState(.ready)
            throw InferenceError.backendInitializationFailed(
                detail: "Tokenization returned zero tokens for the prompt."
            )
        }

        logger.info("Prompt tokenized: \(promptTokens.count) tokens")

        // ── Step 2: Create the token stream controller ─────────────────
        let controller = TokenStreamController()
        self.streamController = controller
        controller.startGeneration()

        // ── Step 3: Get the raw stream from the bridge ─────────────────
        let rawStream = await bridge.generateStream(
            promptTokens: promptTokens,
            params: parameters
        )

        // ── Step 4: Bridge the raw stream to the typed stream ──────────
        // We consume the raw (tokenID, text, isEog) tuples and emit
        // proper EmittedToken values through the controller.
        let consumerTask = Task { [weak self = self] in
            for await (tokenID, rawText, isEog) in rawStream {
                guard !Task.isCancelled else { break }
                controller.emitToken(
                    tokenID: Int(tokenID),
                    rawText: rawText,
                    isEog: isEog
                )

                if isEog {
                    break
                }
            }

            // Generation finished — update state
            controller.finishGeneration()
            await self?.updateStateOnGenerationComplete()
        }

        // ── Step 5: Return the consumer stream ─────────────────────────
        // The caller iterates this AsyncStream to receive EmittedToken values.
        let consumerStream = controller.createStream()

        // When the consumer stops iterating (breaks out of the for-await loop),
        // we need to cancel the generation task.
        // We handle this by wrapping the stream with an on-termination handler.
        return AsyncStream { continuation in
            let innerContinuation = consumerStream.makeAsyncIterator()

            Task {
                var iterator = consumerStream.makeAsyncIterator()
                while let token = await iterator.next() {
                    continuation.yield(token)
                }
                consumerTask.cancel()
                continuation.finish()
            }
        }
    }

    // MARK: - Generation from Existing Context (Phase 3)

    /// Generate tokens from the existing KV cache without processing a new prompt.
    ///
    /// This is the dual-processing fix. After the SmartContextEvictor rebuilds
    /// the context (resetContext + processPromptAfterEviction), the KV cache
    /// already contains the conversation history. Calling generate() would
    /// re-tokenize and re-process everything. This method skips that step
    /// and goes straight to autoregressive generation.
    ///
    /// The method needs to know the assistant header tokens for the chat
    /// template format being used, so it can append them to the KV cache
    /// before starting generation. These are provided via the
    /// assistantHeaderTokens parameter.
    ///
    /// - Parameters:
    ///   - assistantHeaderTokens: The tokens for the assistant header
    ///     (e.g., "<|start_header_id|>assistant<|end_header_id|>\n\n" for Llama-3).
    ///     These will be processed into the KV cache before generation starts.
    ///   - parameters: Sampling and generation parameters.
    /// - Returns: AsyncStream of EmittedToken values.
    /// - Throws: InferenceError if the engine is not in .ready state.
    func generateFromExistingContext(
        assistantHeaderTokens: [Int32],
        parameters: GenerationParameters
    ) async throws -> AsyncStream<EmittedToken> {
        guard _state == .ready else {
            throw InferenceError.backendInitializationFailed(
                detail: "Cannot generate while in \(_state) state. Load a model first."
            )
        }

        updateState(.generating)
        logger.info("Starting generation from existing context. Assistant header: \(assistantHeaderTokens.count) tokens")

        // ── Stop token sanitization ──
        // The assistant header tokens are injected into the KV cache before
        // generation starts. If any of these tokens happen to be stop tokens
        // (e.g., a control token in the template), generation would end
        // immediately. We strip them out as a safety measure.
        let stopTokenIDs = Set(
            parameters.stopTokens.flatMap { stopStr in
                await bridge.tokenize(text: stopStr, addBOS: false, special: true)
            }
        )
        let sanitizedHeaderTokens = assistantHeaderTokens.filter { !stopTokenIDs.contains($0) }

        if sanitizedHeaderTokens.count != assistantHeaderTokens.count {
            logger.warning("Stripped \(assistantHeaderTokens.count - sanitizedHeaderTokens.count) stop tokens from assistant header. Original: \(assistantHeaderTokens.count), sanitized: \(sanitizedHeaderTokens.count)")
        }

        // Process the assistant header tokens into the existing KV cache
        if !sanitizedHeaderTokens.isEmpty {
            try await bridge.processPrompt(tokens: sanitizedHeaderTokens)
        }

        // Create the token stream controller
        let controller = TokenStreamController()
        self.streamController = controller
        controller.startGeneration()

        // Get the raw stream from the bridge — pass empty prompt tokens
        // since the prompt is already in the KV cache. The bridge's
        // generateStream expects prompt tokens, but we can pass an empty
        // array and it will start generating from the last token in the
        // KV cache. We use a special "continue generation" path.
        let rawStream = await bridge.generateStreamFromExistingContext(
            params: parameters
        )

        // Bridge the raw stream to the typed stream
        let consumerTask = Task { [weak self = self] in
            for await (tokenID, rawText, isEog) in rawStream {
                guard !Task.isCancelled else { break }
                controller.emitToken(
                    tokenID: Int(tokenID),
                    rawText: rawText,
                    isEog: isEog
                )
                if isEog { break }
            }

            controller.finishGeneration()
            await self?.updateStateOnGenerationComplete()
        }

        return AsyncStream { continuation in
            Task {
                var iterator = controller.createStream().makeAsyncIterator()
                while let token = await iterator.next() {
                    continuation.yield(token)
                }
                consumerTask.cancel()
                continuation.finish()
            }
        }
    }

    // MARK: - Context Reset

    func resetContext() async {
        guard _state == .ready || _state == .generating else { return }
        await bridge.clearKVCache()
        logger.info("Context reset. KV cache cleared.")
    }

    // MARK: - Eviction Support (Phase 2)

    /// Tokenize text using the loaded model's tokenizer.
    ///
    /// This is exposed for the ChatState's context eviction flow: after
    /// evicting old turns, the remaining conversation must be re-tokenized
    /// and re-processed into the KV cache.
    ///
    /// - Parameters:
    ///   - text: The text to tokenize.
    ///   - addBOS: Whether to prepend the BOS token.
    ///   - special: Whether to allow special token parsing.
    /// - Returns: Array of token IDs (as Int32, matching llama_token).
    func tokenizeForEviction(
        text: String,
        addBOS: Bool,
        special: Bool
    ) async -> [Int32] {
        await bridge.tokenize(text: text, addBOS: addBOS, special: special)
    }

    /// Process prompt tokens into the KV cache after context eviction.
    ///
    /// After evicting old turns and resetting the KV cache, this method
    /// re-processes the remaining conversation tokens so the model has
    /// the correct context for the next generation.
    ///
    /// - Parameter tokens: The tokenized prompt to process.
    /// - Throws: InferenceError if processing fails.
    func processPromptAfterEviction(tokens: [Int32]) async throws {
        guard _state == .ready else {
            throw InferenceError.contextInvalidated
        }
        try await bridge.processPrompt(tokens: tokens)
        logger.info("Re-processed prompt after eviction: \(tokens.count) tokens")
    }

    // MARK: - Memory Statistics

    func memoryStatistics() async -> [String: UInt64] {
        await bridge.getMemoryStatistics()
    }

    // MARK: - Private Helpers

    /// Update the engine state and log the transition.
    private func updateState(_ newState: EngineState) {
        let oldState = _state
        _state = newState
        logger.debug("State transition: \(oldState.description) → \(newState.description)")
    }

    /// Called when generation completes (success, stop token, or error).
    /// Transitions state back to .ready so a new generation can begin.
    private func updateStateOnGenerationComplete() {
        if case .generating = _state {
            updateState(.ready)
            logger.info("Generation complete. Engine ready.")

            // Log metrics if available
            if let metrics = streamController?.lastMetrics {
                logger.info("\(metrics.description)")
            }

            streamController = nil
        }
    }

    /// Format a byte count as a human-readable string.
    private func formatBytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        let mb = Double(bytes) / 1_048_576
        if gb >= 1.0 {
            return String(format: "%.2f GB", gb)
        } else {
            return String(format: "%.0f MB", mb)
        }
    }
}

// MARK: - Console Test Driver

/// A simple test driver that exercises the inference engine from the
/// Xcode console. This is the Phase 1 deliverable: load a GGUF model
/// and stream text to the console.
///
/// Usage (call from your app's AppDelegate or SwiftUI entry point):
/// ```swift
/// Task.detached(priority: .userInitiated) {
///     await ConsoleDriver.run()
/// }
/// ```
enum ConsoleDriver {

    /// Run the console test with a hardcoded model path.
    ///
    /// - Parameter modelPath: Absolute path to the .gguf file.
    ///       For sideloaded apps, this should be in the app's
    ///       Documents or Application Support directory.
    static func run(modelPath: String? = nil) async {
        let engine = InferenceOrchestrator()

        // ── Locate the model ──────────────────────────────────────────
        let resolvedPath: String
        if let modelPath = modelPath {
            resolvedPath = modelPath
        } else {
            // Default: look in the app's Documents directory
            let documentsDir = NSSearchPathForDirectoriesInDomains(
                .documentDirectory, .userDomainMask, true
            ).first ?? ""
            resolvedPath = (documentsDir as NSString).appendingPathComponent("model.gguf")
        }

        let modelURL = URL(fileURLWithPath: resolvedPath)

        print("══════════════════════════════════════════════════════")
        print("  NeuraL — Phase 1 Console Driver")
        print("══════════════════════════════════════════════════════")
        print()

        // ── Memory snapshot ────────────────────────────────────────────
        let memoryManager = MemoryManager.shared
        let snapshot = await memoryManager.snapshot()
        print("Device: \(snapshot.deviceTier)")
        print(snapshot.description)
        print()

        // ── Load the model ─────────────────────────────────────────────
        print("Loading model: \(resolvedPath)")
        print()

        do {
            try await engine.loadModel(
                from: modelURL,
                configuration: .default
            )
        } catch {
            print("❌ Model loading failed: \(error)")
            print()
            print("Troubleshooting:")
            print("  1. Ensure the .gguf file exists at the specified path")
            print("  2. Check that the model is a supported architecture (Llama, Mistral, Phi)")
            print("  3. Verify the model is quantized (Q4_K_M recommended)")
            print("  4. Confirm the device has enough RAM for the model size")
            return
        }

        // ── Print model metadata ───────────────────────────────────────
        if let metadata = await engine.loadedModelMetadata {
            print("Model loaded successfully:")
            print("  Architecture:   \(metadata.architecture)")
            print("  Layers:         \(metadata.layerCount)")
            print("  Embedding dim:  \(metadata.embeddingDimension)")
            print("  Vocab size:     \(metadata.vocabularySize)")
            print("  Train ctx:      \(metadata.trainingContextLength)")
            print("  Quantization:   \(metadata.quantization)")
            print("  File size:      \(metadata.fileSize) bytes")
            print()
        }

        // ── Generate text ──────────────────────────────────────────────
        let prompt = "Once upon a time in a land far away,"
        print("Prompt: \"\(prompt)\"")
        print()
        print("─── Generation Start ───")

        do {
            let stream = try await engine.generate(
                prompt: prompt,
                parameters: .chat
            )

            var fullText = ""
            for await token in stream {
                // Print each token immediately for the typewriter effect
                print(token.text, terminator: "")
                fflush(stdout)
                fullText += token.text
            }

            print()
            print("─── Generation End ───")
            print()

            // ── Print metrics ──────────────────────────────────────────
            let stats = await engine.memoryStatistics()
            print("Memory statistics:")
            for (key, value) in stats.sorted(by: { $0.key < $1.key }) {
                let mb = Double(value) / 1_048_576
                print("  \(key): \(String(format: "%.1f", mb)) MB")
            }
            print()

            let contextLen = await engine.activeContextLength
            let maxCtx = await engine.maxContextLength
            print("Context: \(contextLen)/\(maxCtx) tokens used")
        } catch {
            print("❌ Generation failed: \(error)")
        }

        // ── Unload ─────────────────────────────────────────────────────
        await engine.unloadModel()
        print()
        print("Model unloaded. Engine idle.")
        print("══════════════════════════════════════════════════════")
    }

    /// Interactive mode: read prompts from the console and generate responses.
    /// Useful for manual testing and prompt engineering.
    static func runInteractive(modelPath: String? = nil) async {
        let engine = InferenceOrchestrator()

        // Load model
        let resolvedPath = modelPath ?? {
            let documentsDir = NSSearchPathForDirectoriesInDomains(
                .documentDirectory, .userDomainMask, true
            ).first ?? ""
            return (documentsDir as NSString).appendingPathComponent("model.gguf")
        }()

        let modelURL = URL(fileURLWithPath: resolvedPath)

        print("Loading model: \(resolvedPath)")
        do {
            try await engine.loadModel(from: modelURL, configuration: .default)
            print("Model loaded. Type your prompts below (or 'quit' to exit).")
            print()
        } catch {
            print("Failed to load model: \(error)")
            return
        }

        // Interactive loop
        while true {
            print("You: ", terminator: "")
            fflush(stdout)

            guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !input.isEmpty else {
                continue
            }

            if input.lowercased() == "quit" {
                break
            }

            print("Assistant: ", terminator: "")
            fflush(stdout)

            do {
                let stream = try await engine.generate(
                    prompt: input,
                    parameters: .chat
                )

                for await token in stream {
                    print(token.text, terminator: "")
                    fflush(stdout)
                }
                print()
                print()
            } catch {
                print("Error: \(error)")
            }

            // Reset context for next turn (or continue the conversation
            // by NOT resetting — the KV cache retains the history).
            // Uncomment the next line to reset between turns:
            // await engine.resetContext()
        }

        await engine.unloadModel()
        print("Goodbye!")
    }
}
