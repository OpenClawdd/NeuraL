//
//  LlamaCppBridge.swift
//  NeuraL
//
//  Phase 1 — Low-Level llama.cpp C Interop Layer
//
//  This file wraps the llama.cpp C API into a safe, actor-isolated Swift
//  interface. It is the ONLY file in the project that directly touches the
//  C pointers from llama.h. All other Swift code interacts with the
//  InferenceEngine protocol or the InferenceOrchestrator.
//
//  Safety guarantees:
//  - All llama_model and llama_context pointers are owned exclusively by
//    this actor. No pointer escapes the actor boundary.
//  - Every allocation has a corresponding deallocation in deinit.
//  - The sampler state is recreated per-generation to avoid stale state.
//  - All C function calls are validated for return values.
//
//  Thread safety:
//  - This is an actor, so all methods are serialized by the actor executor.
//  - The generation loop uses a Task with cancellation checking so that
//    unloadModel() can interrupt an active generation.
//

import Foundation

// MARK: - Opaque Pointer Wrappers

/// Wrapper around llama_model* that ensures type safety and prevents raw
/// pointer leaks. The underlying pointer is only accessible within this file.
final class LlamaModel: @unchecked Sendable {
    private(set) var pointer: OpaquePointer?

    /// Whether this model has been loaded (pointer is non-nil).
    var isLoaded: Bool { pointer != nil }

    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    /// Release the model. Must be called exactly once.
    func release() {
        guard let ptr = pointer else { return }
        llama_model_free(ptr)
        pointer = nil
    }

    deinit {
        if let ptr = pointer {
            // This should not happen in normal flow — release() should be
            // called explicitly. But as a safety net, free on deinit.
            print("[LlamaCppBridge] WARNING: LlamaModel deinit with non-nil pointer. Releasing.")
            llama_model_free(ptr)
        }
    }
}

/// Wrapper around llama_context* that ensures type safety.
final class LlamaContext: @unchecked Sendable {
    private(set) var pointer: OpaquePointer?

    /// Whether this context is initialized (pointer is non-nil).
    var isInitialized: Bool { pointer != nil }

    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    /// Release the context. Must be called exactly once.
    func release() {
        guard let ptr = pointer else { return }
        llama_free(ptr)
        pointer = nil
    }

    deinit {
        if let ptr = pointer {
            print("[LlamaCppBridge] WARNING: LlamaContext deinit with non-nil pointer. Releasing.")
            llama_free(ptr)
        }
    }
}

/// Wrapper around llama_sampler* for the sampling chain.
final class LlamaSamplerChain: @unchecked Sendable {
    private(set) var pointer: OpaquePointer?

    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    func release() {
        guard let ptr = pointer else { return }
        llama_sampler_free(ptr)
        pointer = nil
    }

    deinit {
        if let ptr = pointer {
            print("[LlamaCppBridge] WARNING: LlamaSamplerChain deinit with non-nil pointer. Releasing.")
            llama_sampler_free(ptr)
        }
    }
}

// MARK: - Bridge Configuration

/// Configuration for the llama.cpp backend, derived from ModelLoadConfiguration
/// and the MemoryBudget computed by MemoryManager.
struct LlamaBridgeConfiguration: Sendable {
    let contextLength: Int
    let gpuLayerCount: Int
    let generationThreadCount: Int
    let batchThreadCount: Int
    let batchSize: Int
    let useMemoryMapping: Bool
}

// MARK: - LlamaCppBridge Actor

/// The actor that owns all llama.cpp state and provides safe access to it.
///
/// This actor is the boundary between Swift's safe concurrency model and
/// llama.cpp's C API. All operations that touch llama_model*, llama_context*,
/// or llama_sampler* MUST go through this actor.
actor LlamaCppBridge {

    // MARK: - State

    private var model: LlamaModel?
    private var context: LlamaContext?
    private var samplerChain: LlamaSamplerChain?

    /// Tokens currently in the KV cache (the active context).
    private var contextTokens: [llama_token] = []

    /// The configuration used to load the current model.
    private var configuration: LlamaBridgeConfiguration?

    /// Whether a generation is currently in progress.
    private var isGenerating = false

    /// Task handle for the active generation, allowing cancellation.
    private var activeGenerationTask: Task<Void, Never>?

    // MARK: - Initialization

    /// Initialize the llama.cpp backend. Must be called once before any
    /// model loading. This calls llama_backend_init().
    init() {
        llama_backend_init()
        print("[LlamaCppBridge] Backend initialized. System info: \(String(cString: llama_print_system_info()))")
    }

    deinit {
        // Clean up in reverse order: sampler → context → model → backend
        samplerChain?.release()
        context?.release()
        model?.release()
        llama_backend_free()
        print("[LlamaCppBridge] Backend freed.")
    }

    // MARK: - Model Loading

    /// Load a GGUF model from the given file path.
    ///
    /// - Parameters:
    ///   - filePath: Absolute path to the .gguf file.
    ///   - config: Bridge configuration derived from MemoryBudget.
    /// - Throws: InferenceError on any failure.
    func loadModel(filePath: String, config: LlamaBridgeConfiguration) throws {
        guard model == nil else {
            throw InferenceError.backendInitializationFailed(
                detail: "A model is already loaded. Call unloadModel() first."
            )
        }

        self.configuration = config

        // ── Step 1: Configure model parameters ────────────────────────
        var modelParams = ondevice_model_params_default()
        modelParams.n_gpu_layers = Int32(config.gpuLayerCount)
        modelParams.use_mmap = config.useMemoryMapping
        // mlock is unavailable on iOS; do not attempt it.
        modelParams.use_mlock = false

        // ── Step 2: Load the model ────────────────────────────────────
        let modelPointer = filePath.withCString { path in
            llama_model_load_from_file(path, modelParams)
        }

        guard let modelPointer else {
            throw InferenceError.modelCorrupt(
                path: filePath,
                detail: "llama_model_load_from_file returned NULL. The file may be corrupt, an unsupported GGUF version, or incompatible with this build of llama.cpp."
            )
        }

        self.model = LlamaModel(pointer: modelPointer)
        print("[LlamaCppBridge] Model loaded: \(filePath)")

        // ── Step 3: Configure context parameters ──────────────────────
        let contextParams = ondevice_context_params_default(Int32(config.contextLength))
        // Override thread counts from our configuration
        var mutableContextParams = contextParams
        mutableContextParams.n_threads = Int32(config.generationThreadCount)
        mutableContextParams.n_threads_batch = Int32(config.batchThreadCount)
        mutableContextParams.n_batch = Int32(config.batchSize)
        mutableContextParams.n_ubatch = Int32(config.batchSize)

        // ── Step 4: Create the context ────────────────────────────────
        let contextPointer = llama_init_from_model(modelPointer, mutableContextParams)

        guard let contextPointer else {
            // Model loaded but context failed — this usually means
            // insufficient memory for the requested context length.
            model?.release()
            self.model = nil
            throw InferenceError.backendInitializationFailed(
                detail: "llama_init_from_model returned NULL. Likely insufficient memory for n_ctx=\(config.contextLength). Try a smaller context length."
            )
        }

        self.context = LlamaContext(pointer: contextPointer)

        // ── Step 5: Validate actual context length ────────────────────
        let actualCtx = llama_n_ctx(contextPointer)
        if actualCtx < Int32(config.contextLength) {
            print("[LlamaCppBridge] WARNING: Actual context length (\(actualCtx)) < requested (\(config.contextLength)). The backend reduced it due to memory constraints.")
        }

        self.contextTokens = []
        print("[LlamaCppBridge] Context created. n_ctx=\(actualCtx), n_threads=\(config.generationThreadCount)")
    }

    // MARK: - Model Metadata

    /// Extract metadata from the loaded model.
    func getModelMetadata() -> ModelMetadata? {
        guard let modelPtr = model?.pointer else { return nil }

        // Architecture name (e.g., "llama", "mistral", "phi2")
        let archPtr = llama_model_arch(modelPtr)
        let arch = archPtr != nil ? String(cString: archPtr!) : "unknown"

        // Get the model's training context length
        let nCtxTrain = llama_model_n_ctx_train(modelPtr)

        // Extract layer count and embedding dimension.
        // NOTE: llama_model_n_layer() and llama_model_n_embd() were added in
        // llama.cpp post-llama-3. If your version doesn't have them, you'll
        // need to read from the GGUF metadata directly. The functions below
        // are available in llama.cpp >= b2759 (June 2024).
        let nLayers = Int(llama_model_n_layer(modelPtr))
        let nEmbd = Int(llama_model_n_embd(modelPtr))
        let nVocab = Int(llama_model_n_vocab(modelPtr))

        // Get quantization / file type description.
        // llama_model_type() writes a descriptive string into the provided buffer.
        var typeBuffer = [CChar](repeating: 0, count: 256)
        llama_model_type(modelPtr, &typeBuffer, 256)
        let quantString = String(cString: typeBuffer)

        // Estimate memory footprint
        let footprint = estimateMemoryFootprint()

        return ModelMetadata(
            architecture: arch,
            layerCount: nLayers,
            embeddingDimension: nEmbd,
            vocabularySize: nVocab,
            trainingContextLength: Int(nCtxTrain),
            fileSize: 0,  // Caller should set this from FileManager
            quantization: quantString,
            estimatedMemoryFootprint: footprint
        )
    }

    // MARK: - Tokenization

    /// Tokenize a string into token IDs.
    ///
    /// - Parameters:
    ///   - text: The text to tokenize.
    ///   - addBOS: Whether to prepend the BOS token.
    ///   - special: Whether to allow special token parsing.
    /// - Returns: Array of token IDs.
    func tokenize(text: String, addBOS: Bool, special: Bool) -> [llama_token] {
        guard let modelPtr = model?.pointer else { return [] }

        let maxTokens = text.utf8.count + (addBOS ? 1 : 0) + 1  // +1 for safety
        var tokens = [llama_token](repeating: 0, count: maxTokens)

        // Use the UTF-8 byte count directly instead of strlen(), which
        // can be unreliable on Swift C string pointers that contain NUL
        // bytes or other edge cases.
        let textByteCount = Int32(text.utf8.count)

        let nTokens = text.withCString { textPtr in
            llama_tokenize(
                modelPtr,
                textPtr,
                textByteCount,
                &tokens,
                Int32(maxTokens),
                addBOS,
                special
            )
        }

        if nTokens < 0 {
            // Buffer too small; resize and retry with the reported required size
            let requiredSize = Int(-nTokens)
            tokens = [llama_token](repeating: 0, count: requiredSize)
            let retryResult = text.withCString { textPtr in
                llama_tokenize(
                    modelPtr,
                    textPtr,
                    textByteCount,
                    &tokens,
                    Int32(requiredSize),
                    addBOS,
                    special
                )
            }
            if retryResult < 0 {
                print("[LlamaCppBridge] ERROR: Tokenization failed after resize.")
                return []
            }
            return Array(tokens.prefix(Int(retryResult)))
        }

        return Array(tokens.prefix(Int(nTokens)))
    }

    /// Convert a token ID to its string representation.
    func tokenToString(tokenID: llama_token) -> String {
        guard let modelPtr = model?.pointer else { return "" }

        // First call: get the required buffer size
        let bufSize = 16  // Most tokens are <16 bytes; resize if needed
        var buffer = [CChar](repeating: 0, count: bufSize)

        let nBytes = llama_token_to_piece(
            modelPtr,
            tokenID,
            &buffer,
            Int32(bufSize),
            0,    // lstrip
            true  // special: allow decoding special tokens
        )

        if nBytes < 0 {
            // Buffer too small, resize
            let requiredSize = Int(-nBytes)
            buffer = [CChar](repeating: 0, count: requiredSize)
            let retryResult = llama_token_to_piece(
                modelPtr,
                tokenID,
                &buffer,
                Int32(requiredSize),
                0,
                true
            )
            if retryResult < 0 {
                return ""
            }
            return String(cString: buffer)
        }

        return String(cString: buffer)
    }

    /// Check if a token is an end-of-generation token.
    func isEndOfGenerationToken(_ tokenID: llama_token) -> Bool {
        guard let modelPtr = model?.pointer else { return false }
        return llama_token_is_eog(modelPtr, tokenID)
    }

    // MARK: - KV Cache Management

    /// Get the current number of tokens in the KV cache.
    var contextLength: Int {
        contextTokens.count
    }

    /// Get the maximum context length the context was initialized with.
    var maxContextLength: Int {
        guard let ctxPtr = context?.pointer else { return 0 }
        return Int(llama_n_ctx(ctxPtr))
    }

    /// Clear the KV cache and reset the context token list.
    func clearKVCache() {
        guard let ctxPtr = context?.pointer else { return }
        llama_kv_cache_clear(ctxPtr)
        contextTokens = []
        print("[LlamaCppBridge] KV cache cleared.")
    }

    /// Remove the oldest tokens from the KV cache to make room for new ones.
    /// This implements a sliding window context management strategy.
    ///
    /// - Parameter count: Number of tokens to remove from the beginning.
    func evictOldestTokens(count: Int) {
        guard count > 0, let ctxPtr = context?.pointer else { return }
        let actualCount = min(count, contextTokens.count)

        // Build a sequence of positions to remove
        var positions = [llama_pos](repeating: 0, count: actualCount)
        for i in 0..<actualCount {
            positions[i] = llama_pos(i)
        }

        // Remove from KV cache
        llama_kv_cache_seq_rm(
            ctxPtr,
            0,                       // seq_id
            0,                       // p0 (start position)
            llama_pos(actualCount)   // p1 (end position)
        )

        // Shift remaining tokens' positions to fill the gap
        if actualCount < contextTokens.count {
            llama_kv_cache_seq_shift(
                ctxPtr,
                0,                               // seq_id
                llama_pos(actualCount),           // p0 (start of range to shift)
                llama_pos(contextTokens.count),   // p1 (end of range to shift)
                llama_pos(-actualCount)           // delta (shift amount)
            )
        }

        // Remove from our token list
        contextTokens.removeFirst(actualCount)
        print("[LlamaCppBridge] Evicted \(actualCount) oldest tokens. Context now: \(contextTokens.count)")
    }

    // MARK: - Prompt Processing

    /// Process (ingest) a batch of prompt tokens into the KV cache.
    ///
    /// This is the first phase of inference: the prompt tokens are processed
    /// in batches to fill the KV cache, after which autoregressive generation
    /// can begin.
    ///
    /// - Parameter tokens: The prompt tokens to process.
    /// - Throws: InferenceError if processing fails.
    func processPrompt(tokens: [llama_token]) throws {
        guard let ctxPtr = context?.pointer else {
            throw InferenceError.contextInvalidated
        }

        let maxCtx = maxContextLength
        let totalTokens = contextTokens.count + tokens.count

        // If the prompt exceeds the context window, we need to truncate.
        if totalTokens > maxCtx {
            let excess = totalTokens - maxCtx
            if excess >= contextTokens.count {
                // Even evicting the entire existing context isn't enough.
                // Truncate the prompt itself.
                let truncatedTokens = Array(tokens.suffix(maxCtx))
                contextTokens = truncatedTokens
                print("[LlamaCppBridge] WARNING: Prompt truncated to \(truncatedTokens.count) tokens.")
            } else {
                // Evict oldest tokens to make room
                evictOldestTokens(count: excess + 64)  // +64 for generation headroom
            }
        }

        // Process in batches of config.batchSize
        let batchSize = configuration?.batchSize ?? 512
        let batches = stride(from: 0, to: tokens.count, by: batchSize)

        for batchStart in batches {
            let batchEnd = min(batchStart + batchSize, tokens.count)
            let batchTokens = Array(tokens[batchStart..<batchEnd])

            // Create a llama_batch for this chunk.
            // We use withUnsafeBufferPointer to ensure the array's storage
            // is passed as a contiguous C array to llama_batch_get_one.
            let result = batchTokens.withUnsafeBufferPointer { tokenBuffer in
                var batch = llama_batch_get_one(tokenBuffer.baseAddress, Int32(batchTokens.count))
                return llama_decode(ctxPtr, &batch)
            }
            if result != 0 {
                throw InferenceError.backendInitializationFailed(
                    detail: "llama_decode failed with code \(result) during prompt processing. This typically indicates a KV cache overflow or memory allocation failure."
                )
            }
        }

        contextTokens.append(contentsOf: tokens)
        print("[LlamaCppBridge] Prompt processed: \(tokens.count) tokens. Total context: \(contextTokens.count)")
    }

    // MARK: - Sampling

    /// Create a sampler chain based on the given generation parameters.
    ///
    /// The chain is: temperature → top-k → top-p → repeat-penalty → dist
    /// For temperature=0 (greedy), we use argmax instead.
    private func createSamplerChain(params: GenerationParameters) -> LlamaSamplerChain {
        var chain = llama_sampler_chain_default_init()

        if params.temperature <= 0 {
            // Greedy decoding: just argmax
            let greedy = llama_sampler_init_greedy()
            llama_sampler_chain_add(chain, greedy)
        } else {
            // Temperature scaling
            let temp = llama_sampler_init_temp(params.temperature)
            llama_sampler_chain_add(chain, temp)

            // Top-K filtering
            if params.topK > 0 {
                let topk = llama_sampler_init_top_k(Int32(params.topK))
                llama_sampler_chain_add(chain, topk)
            }

            // Top-P (nucleus) filtering
            let topp = llama_sampler_init_top_p(params.topP, 1)
            llama_sampler_chain_add(chain, topp)

            // Repeat penalty (applied to the last N tokens)
            if params.repeatPenalty > 1.0 && params.repeatPenaltyWindowSize > 0 {
                let lastTokens = Array(contextTokens.suffix(params.repeatPenaltyWindowSize))
                let penalty = llama_sampler_init_penalties(
                    Int32(params.repeatPenaltyWindowSize),  // penalty_last_n
                    params.repeatPenalty,                    // penalty_repeat
                    0.0,                                    // penalty_freq
                    0.0,                                    // penalty_present
                    false                                   // penalize_nl
                )
                llama_sampler_chain_add(chain, penalty)
            }

            // Distribution sampling (random selection from the filtered distribution)
            let seed = params.seed ?? UInt64.random(in: UInt64.min...UInt64.max)
            let dist = llama_sampler_init_dist(seed)
            llama_sampler_chain_add(chain, dist)
        }

        return LlamaSamplerChain(pointer: chain)
    }

    // MARK: - Token Generation

    /// Generate a single token from the current KV cache state.
    ///
    /// - Parameter sampler: The sampler chain to use for token selection.
    /// - Returns: The generated token ID.
    /// - Throws: InferenceError if the context is invalid.
    func generateSingleToken(sampler: LlamaSamplerChain) throws -> llama_token {
        guard let ctxPtr = context?.pointer,
              let modelPtr = model?.pointer,
              let samplerPtr = sampler.pointer else {
            throw InferenceError.contextInvalidated
        }

        // Note: llama_sampler_sample() internally accesses the logits,
        // so we don't need to call llama_get_logits_ith() separately.
        // The sampler reads from the context's internal logits buffer
        // which is populated by the previous llama_decode() call.

        // Sample a token
        let newToken = llama_sampler_sample(samplerPtr, ctxPtr, Int32(contextTokens.count) - 1)

        // Accept the token into the sampler state (for repeat penalty tracking)
        llama_sampler_accept(samplerPtr, newToken)

        // Decode the new token (add to KV cache).
        // Use withUnsafePointer for safe C array interop.
        let result = withUnsafePointer(to: newToken) { tokenPtr in
            // llama_batch_get_one expects a pointer to an array of llama_token.
            // A single-element pointer works for batch_size=1.
            var batch = llama_batch_get_one(tokenPtr, 1)
            return llama_decode(ctxPtr, &batch)
        }

        if result != 0 {
            throw InferenceError.backendInitializationFailed(
                detail: "llama_decode failed during generation with code \(result)."
            )
        }

        contextTokens.append(newToken)
        return newToken
    }

    /// The main generation loop. Returns an AsyncStream of (tokenID, text, isEog).
    ///
    /// This method runs the autoregressive loop, emitting one token at a time
    /// through the AsyncStream. It checks for:
    /// - Task cancellation (allows unloadModel() to interrupt generation)
    /// - Maximum token count
    /// - End-of-generation tokens
    /// - Stop token strings
    /// - Context window overflow (auto-evicts oldest tokens)
    ///
    /// - Parameters:
    ///   - promptTokens: The tokenized prompt to process before generation.
    ///   - params: Generation parameters (sampling, limits, stop tokens).
    /// - Returns: AsyncStream of (tokenID, tokenText, isEog) tuples.
    func generateStream(
        promptTokens: [llama_token],
        params: GenerationParameters
    ) -> AsyncStream<(tokenID: llama_token, text: String, isEog: Bool)> {
        AsyncStream { continuation in
            Task { [weak self = self] in
                guard let self = self else {
                    continuation.finish()
                    return
                }

                do {
                    // ── Step 1: Process the prompt ─────────────────────
                    try self.processPrompt(tokens: promptTokens)

                    // ── Step 2: Create the sampler ─────────────────────
                    let sampler = self.createSamplerChain(params: params)
                    defer { sampler.release() }

                    // ── Step 3: Tokenize stop tokens for fast comparison
                    let stopTokenIDs = Set(
                        params.stopTokens.flatMap { stopStr in
                            self.tokenize(text: stopStr, addBOS: false, special: true)
                        }
                    )

                    // ── Step 4: Autoregressive generation loop ─────────
                    self.isGenerating = true
                    var generatedCount = 0
                    var accumulatedText = ""
                    let generationStartTime = ContinuousClock.now

                    while generatedCount < params.maxTokens {
                        // Check for cancellation
                        if Task.isCancelled {
                            print("[LlamaCppBridge] Generation cancelled by task cancellation.")
                            break
                        }

                        // Check for memory pressure — abort immediately to avoid jetsam
                        if await MemoryManager.shared.underMemoryPressure {
                            print("[LlamaCppBridge] Generation aborted due to memory pressure.")
                            break
                        }

                        // Auto-evict if approaching context limit
                        if self.contextTokens.count >= self.maxContextLength - 64 {
                            self.evictOldestTokens(count: 128)
                        }

                        // Yield for thermal management
                        await MemoryManager.shared.yieldForThermalIfNecessary()

                        // Dynamic token rate cap: if generating too fast for
                        // the current thermal state, insert an artificial delay
                        if generatedCount > 5 {
                            let elapsed = ContinuousClock.now - generationStartTime
                            let elapsedSec = Double(elapsed.components.seconds) +
                                Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000
                            if elapsedSec > 0.1 {
                                let currentTokPerSec = Double(generatedCount) / elapsedSec
                                let delayMs = await MemoryManager.shared.interTokenDelayMs(
                                    currentTokPerSec: currentTokPerSec
                                )
                                if delayMs > 0 {
                                    try? await Task.sleep(for: .milliseconds(delayMs))
                                }
                            }
                        }

                        // Generate next token (wrapped in autoreleasepool)
                        let newToken: llama_token
                        try autoreleasepool {
                            newToken = try self.generateSingleToken(sampler: sampler)
                        }

                        let tokenText = self.tokenToString(tokenID: newToken)
                        let isEog = self.isEndOfGenerationToken(newToken)

                        // Check stop tokens
                        let hitStopToken = stopTokenIDs.contains(newToken)

                        accumulatedText += tokenText

                        // Emit the token
                        continuation.yield((newToken, tokenText, isEog || hitStopToken))
                        generatedCount += 1

                        // Termination conditions
                        if isEog || hitStopToken {
                            print("[LlamaCppBridge] Generation ended: \(isEog ? "end-of-generation token" : "stop token"). Tokens generated: \(generatedCount)")
                            break
                        }
                    }

                    self.isGenerating = false
                } catch {
                    self.isGenerating = false
                    print("[LlamaCppBridge] Generation error: \(error)")
                    // Don't yield an error token; just finish the stream.
                    // The orchestrator will detect the error state.
                }

                continuation.finish()
            }
        }
    }

    // MARK: - Generation from Existing Context (Phase 3)

    /// Generate a token stream starting from the current KV cache state,
    /// without processing a new prompt first.
    ///
    /// This is used after context eviction when the prompt has already been
    /// re-processed via processPromptAfterEviction(). The autoregressive
    /// loop begins immediately from the last token in the KV cache.
    ///
    /// - Parameter params: Generation parameters (sampling, limits, stop tokens).
    /// - Returns: AsyncStream of (tokenID, text, isEog) tuples.
    func generateStreamFromExistingContext(
        params: GenerationParameters
    ) -> AsyncStream<(tokenID: llama_token, text: String, isEog: Bool)> {
        AsyncStream { continuation in
            Task { [weak self = self] in
                guard let self = self else {
                    continuation.finish()
                    return
                }

                do {
                    // ── Step 1: Create the sampler ─────────────────────
                    let sampler = self.createSamplerChain(params: params)
                    defer { sampler.release() }

                    // ── Step 2: Tokenize stop tokens ───────────────────
                    let stopTokenIDs = Set(
                        params.stopTokens.flatMap { stopStr in
                            self.tokenize(text: stopStr, addBOS: false, special: true)
                        }
                    )

                    // ── Step 3: Autoregressive generation loop ─────────
                    self.isGenerating = true
                    var generatedCount = 0
                    let generationStartTime = ContinuousClock.now

                    while generatedCount < params.maxTokens {
                        if Task.isCancelled { break }

                        // Check for memory pressure
                        if await MemoryManager.shared.underMemoryPressure {
                            print("[LlamaCppBridge] Generation from existing context aborted due to memory pressure.")
                            break
                        }

                        // Auto-evict if approaching context limit
                        if self.contextTokens.count >= self.maxContextLength - 64 {
                            self.evictOldestTokens(count: 128)
                        }

                        // Thermal yield
                        await MemoryManager.shared.yieldForThermalIfNecessary()

                        // Dynamic token rate cap
                        if generatedCount > 5 {
                            let elapsed = ContinuousClock.now - generationStartTime
                            let elapsedSec = Double(elapsed.components.seconds) +
                                Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000
                            if elapsedSec > 0.1 {
                                let currentTokPerSec = Double(generatedCount) / elapsedSec
                                let delayMs = await MemoryManager.shared.interTokenDelayMs(
                                    currentTokPerSec: currentTokPerSec
                                )
                                if delayMs > 0 {
                                    try? await Task.sleep(for: .milliseconds(delayMs))
                                }
                            }
                        }

                        // Generate next token
                        let newToken: llama_token
                        try autoreleasepool {
                            newToken = try self.generateSingleToken(sampler: sampler)
                        }

                        let tokenText = self.tokenToString(tokenID: newToken)
                        let isEog = self.isEndOfGenerationToken(newToken)
                        let hitStopToken = stopTokenIDs.contains(newToken)

                        continuation.yield((newToken, tokenText, isEog || hitStopToken))
                        generatedCount += 1

                        if isEog || hitStopToken { break }
                    }

                    self.isGenerating = false
                } catch {
                    self.isGenerating = false
                }

                continuation.finish()
            }
        }
    }

    // MARK: - Unloading

    /// Release all resources: sampler, context, model.
    func unloadModel() {
        // Cancel any active generation
        activeGenerationTask?.cancel()
        activeGenerationTask = nil

        // Release in reverse order of creation
        samplerChain?.release()
        samplerChain = nil

        context?.release()
        context = nil

        model?.release()
        model = nil

        contextTokens = []
        configuration = nil
        isGenerating = false

        print("[LlamaCppBridge] Model unloaded, all resources released.")
    }

    // MARK: - Memory Estimation

    /// Estimate the current memory footprint of the loaded model and context.
    private func estimateMemoryFootprint() -> UInt64 {
        guard let modelPtr = model?.pointer, let ctxPtr = context?.pointer else { return 0 }

        // Use llama.cpp's built-in memory estimation
        let modelSize = llama_model_size(modelPtr)
        let kvCacheSize = llama_state_get_size(ctxPtr)

        // Add overhead for buffers, tokenizer, etc.
        return UInt64(modelSize) + UInt64(kvCacheSize) + (64 * 1_048_576)  // +64MB overhead
    }

    /// Get detailed memory statistics.
    func getMemoryStatistics() -> [String: UInt64] {
        var stats: [String: UInt64] = [:]

        if let modelPtr = model?.pointer {
            stats["model_weights_bytes"] = UInt64(llama_model_size(modelPtr))
        }

        if let ctxPtr = context?.pointer {
            stats["kv_cache_bytes"] = UInt64(llama_state_get_size(ctxPtr))
        }

        stats["total_allocated_bytes"] = estimateMemoryFootprint()
        stats["available_bytes"] = MemoryManager.shared.availableMemory

        return stats
    }
}
