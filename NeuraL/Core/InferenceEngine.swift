//
//  InferenceEngine.swift
//  NeuraL
//
//  Phase 1 — The Inference Engine Protocol & Configuration Types
//
//  This file defines the contract that all inference backends must conform to.
//  The rest of the application (state manager, UI) depends only on this protocol,
//  never on the concrete llama.cpp or MLX implementation details.
//

import Foundation

// MARK: - Errors

/// Errors that can occur during the inference lifecycle.
enum InferenceError: LocalizedError, CustomStringConvertible, Equatable {
    /// The model file could not be found at the specified path.
    case modelNotFound(path: String)
    /// The model file exists but failed validation (corrupt GGUF, wrong format).
    case modelCorrupt(path: String, detail: String)
    /// Insufficient memory to load the model with the requested configuration.
    case insufficientMemory(requiredBytes: UInt64, availableBytes: UInt64)
    /// The model architecture is not supported by this backend.
    case unsupportedArchitecture(arch: String)
    /// The inference context was invalidated (e.g., model unloaded mid-generation).
    case contextInvalidated
    /// Token generation exceeded the maximum allowed duration or token count.
    case generationLimitExceeded
    /// A threading violation was detected (e.g., calling inference on main actor).
    case threadingViolation(detail: String)
    /// The model was loaded with a different context size than requested.
    case contextSizeMismatch(requested: Int, actual: Int)
    /// The backend failed to initialize (llama.cpp init, Metal setup, etc.)
    case backendInitializationFailed(detail: String)

    var description: String {
        switch self {
        case .modelNotFound(let path):
            return "Model not found at: \(path)"
        case .modelCorrupt(let path, let detail):
            return "Model file corrupt (\(detail)): \(path)"
        case .insufficientMemory(let req, let avail):
            let reqMB = Double(req) / 1_048_576
            let availMB = Double(avail) / 1_048_576
            return String(format: "Insufficient memory: need %.0f MB, have %.0f MB", reqMB, availMB)
        case .unsupportedArchitecture(let arch):
            return "Unsupported model architecture: \(arch)"
        case .contextInvalidated:
            return "Inference context was invalidated"
        case .generationLimitExceeded:
            return "Generation limit exceeded (max tokens or duration)"
        case .threadingViolation(let detail):
            return "Threading violation: \(detail)"
        case .contextSizeMismatch(let requested, let actual):
            return "Context size mismatch: requested \(requested), got \(actual)"
        case .backendInitializationFailed(let detail):
            return "Backend initialization failed: \(detail)"
        }
    }

    var errorDescription: String? { description }
}

// MARK: - Model Configuration

/// Metadata about a GGUF model file, extracted without fully loading the model.
struct ModelMetadata: Sendable {
    /// The model architecture name as stored in GGUF metadata (e.g., "llama", "mistral", "phi2").
    let architecture: String
    /// Number of transformer layers.
    let layerCount: Int
    /// Embedding dimension per layer.
    let embeddingDimension: Int
    /// Vocabulary size.
    let vocabularySize: Int
    /// The context length the model was trained with.
    let trainingContextLength: Int
    /// File size in bytes.
    let fileSize: UInt64
    /// Quantization version string (e.g., "Q4_K_M", "Q5_K_S").
    let quantization: String
    /// Estimated memory footprint when loaded (model weights + overhead).
    let estimatedMemoryFootprint: UInt64
}

/// Configuration for how a model should be loaded and run.
struct ModelLoadConfiguration: Sendable {
    /// Maximum context window size (tokens). The MemoryManager will compute
    /// the safe maximum based on available RAM; this acts as a hard upper bound.
    let maxContextLength: Int

    /// Number of layers to offload to the GPU (Metal). Set to 0 for CPU-only,
    /// or Int.max to offload all layers (recommended for Apple Silicon).
    let gpuLayerCount: Int

    /// Number of threads for autoregressive generation (batch_size=1).
    /// Lower values reduce thermal output at the cost of tokens/sec.
    let generationThreadCount: Int

    /// Number of threads for batched prompt processing.
    /// Can be higher since batched work is bursty and finishes quickly.
    let batchThreadCount: Int

    /// Whether to memory-map the model file. True reduces RSS at the cost of
    /// potential page-in latency during first access. Recommended for iOS.
    let useMemoryMapping: Bool

    /// Batch size for prompt processing (how many tokens to process per
    /// llama_decode call during prompt ingestion).
    let batchSize: Int

    /// Defaults optimized for a 1.5B Q4_K_M model on iPhone 15 Pro.
    static let `default` = ModelLoadConfiguration(
        maxContextLength: 2048,
        gpuLayerCount: Int.max,
        generationThreadCount: 2,
        batchThreadCount: 4,
        useMemoryMapping: true,
        batchSize: 512
    )

    /// Conservative configuration for devices with limited thermal headroom
    /// (e.g., iPhone 13/14 standard, or when thermal state is elevated).
    static let conservative = ModelLoadConfiguration(
        maxContextLength: 1024,
        gpuLayerCount: 0,  // CPU only — avoids GPU thermal hotspot
        generationThreadCount: 1,
        batchThreadCount: 2,
        useMemoryMapping: true,
        batchSize: 256
    )
}

/// Parameters controlling a single generation (completion) request.
struct GenerationParameters: Sendable {
    /// The maximum number of new tokens to generate.
    let maxTokens: Int

    /// Temperature for sampling. Higher = more random, lower = more deterministic.
    /// Set to 0 for greedy decoding (argmax).
    let temperature: Float

    /// Top-p (nucleus) sampling threshold. Tokens are sampled from the smallest
    /// set whose cumulative probability exceeds top_p.
    let topP: Float

    /// Top-k sampling: only consider the top K most probable tokens.
    /// Set to 0 to disable (consider all tokens).
    let topK: Int

    /// Repetition penalty. 1.0 = no penalty. Values > 1.0 discourage repetition.
    let repeatPenalty: Float

    /// Number of recent tokens to apply the repeat penalty to.
    let repeatPenaltyWindowSize: Int

    /// A list of token strings that should stop generation immediately.
    let stopTokens: [String]

    /// Seed for the sampler's RNG. Use a fixed value for reproducible outputs.
    /// Use nil for random seeding.
    let seed: UInt64?

    /// Defaults for general-purpose chat generation.
    static let chat = GenerationParameters(
        maxTokens: 512,
        temperature: 0.7,
        topP: 0.9,
        topK: 40,
        repeatPenalty: 1.1,
        repeatPenaltyWindowSize: 64,
        stopTokens: ["</s>", "<|end|>", "<|im_end|>", "<|eot_id|>"],
        seed: nil
    )

    /// Defaults for deterministic / analytical tasks (code, math, factual Q&A).
    static let deterministic = GenerationParameters(
        maxTokens: 1024,
        temperature: 0.0,
        topP: 1.0,
        topK: 1,
        repeatPenalty: 1.0,
        repeatPenaltyWindowSize: 0,
        stopTokens: ["</s>", "<|end|>", "<|im_end|>", "<|eot_id|>"],
        seed: 42
    )
}

// MARK: - Engine State

/// The lifecycle state of an inference engine.
enum EngineState: Sendable, CustomStringConvertible, Equatable {
    /// The engine is initialized but no model is loaded.
    case idle
    /// A model is currently being loaded into memory. The associated float
    /// represents loading progress from 0.0 to 1.0.
    case loading(progress: Float)
    /// A model is loaded and the engine is ready to accept generation requests.
    case ready
    /// The engine is currently generating tokens.
    case generating
    /// The engine encountered an error and cannot continue.
    case error(InferenceError)
    /// The engine is unloading the model and releasing resources.
    case unloading

    var description: String {
        switch self {
        case .idle: return "Idle"
        case .loading(let p): return String(format: "Loading (%.0f%%)", p * 100)
        case .ready: return "Ready"
        case .generating: return "Generating"
        case .error(let e): return "Error: \(e)"
        case .unloading: return "Unloading"
        }
    }
}

/// A single token emitted during generation, carrying both the text and metadata.
struct EmittedToken: Sendable {
    /// The decoded text for this token. May be an empty string for special tokens,
    /// or a partial UTF-8 sequence (the UI layer must handle accumulation).
    let text: String
    /// The integer token ID from the model's vocabulary.
    let tokenID: Int
    /// Whether this token signals the end of generation.
    let isEndOfGeneration: Bool
    /// Cumulative token count including this token.
    let cumulativeTokenCount: Int
    /// Time elapsed since generation started (seconds).
    let elapsedSeconds: Double
    /// Probability of this token under the sampling distribution (if available).
    let probability: Float?
}

// MARK: - Inference Engine Protocol

/// The protocol that all inference backends must implement.
///
/// Design principles:
/// - All mutation methods are async and should run off the main actor.
/// - Token emission uses AsyncSequence for natural SwiftUI integration.
/// - The protocol is Sendable-safe; implementations must use actors or
///   internal synchronization to protect shared state.
///
/// Lifecycle: idle → loading → ready → generating → ready → unloading → idle
///
/// Error recovery: If the engine enters .error state, the caller must
/// call unloadModel() before attempting to load again.
protocol InferenceEngine: Sendable {
    /// The current state of the engine. Observable for UI binding (Phase 2).
    var state: EngineState { get async }

    /// Metadata for the currently loaded model, or nil if no model is loaded.
    var loadedModelMetadata: ModelMetadata? { get async }

    /// The number of tokens currently in the KV cache (i.e., the active context length).
    var activeContextLength: Int { get async }

    /// The maximum context length the loaded model was configured with.
    var maxContextLength: Int { get async }

    /// Load a GGUF model from the given file URL.
    ///
    /// This method validates the file, checks memory requirements via the
    /// MemoryManager, and initializes the backend. It updates state to
    /// .loading during the process and .ready on success.
    ///
    /// - Parameters:
    ///   - modelURL: File URL to the .gguf model file.
    ///   - configuration: How the model should be loaded and run.
    /// - Throws: InferenceError on any failure.
    func loadModel(from modelURL: URL, configuration: ModelLoadConfiguration) async throws

    /// Unload the current model and release all associated resources.
    ///
    /// Safe to call from any state. After unloading, the engine returns to .idle.
    /// If the engine is in .generating state, this cancels the active generation.
    func unloadModel() async

    /// Generate tokens from a prompt, emitting them as an AsyncSequence.
    ///
    /// The caller iterates the returned sequence to receive tokens in real-time.
    /// Generation continues until maxTokens is reached, a stop token is emitted,
    /// or the caller cancels by breaking out of the iteration.
    ///
    /// This method tokenizes and processes the prompt into the KV cache before
    /// starting generation. If the prompt has already been processed (e.g., after
    /// context eviction and re-processing), use generateFromExistingContext() instead.
    ///
    /// - Parameters:
    ///   - prompt: The full prompt string (will be tokenized internally).
    ///   - parameters: Sampling and generation parameters.
    /// - Returns: An AsyncStream of EmittedToken values.
    /// - Throws: InferenceError if the engine is not in .ready state.
    func generate(
        prompt: String,
        parameters: GenerationParameters
    ) async throws -> AsyncStream<EmittedToken>

    /// Generate tokens from the existing KV cache state without processing a new prompt.
    ///
    /// Use this method after the context has been rebuilt by the SmartContextEvictor
    /// (which already called resetContext() + processPromptAfterEviction()). This
    /// prevents the dual-processing bug where generate() would re-tokenize and
    /// re-process the same prompt that was just loaded into the KV cache.
    ///
    /// The method appends the assistant header token to the existing KV cache
    /// and begins autoregressive generation immediately.
    ///
    /// - Parameter parameters: Sampling and generation parameters.
    /// - Returns: An AsyncStream of EmittedToken values.
    /// - Throws: InferenceError if the engine is not in .ready state.
    func generateFromExistingContext(
        parameters: GenerationParameters
    ) async throws -> AsyncStream<EmittedToken>

    /// Reset the KV cache, clearing all conversation context.
    ///
    /// This allows starting a new conversation without reloading the model.
    /// The model weights remain in memory; only the context is cleared.
    func resetContext() async

    /// Get the memory statistics for the loaded model.
    ///
    /// Returns a dictionary with keys like "model_weights_bytes",
    /// "kv_cache_bytes", "total_allocated_bytes", "available_bytes".
    func memoryStatistics() async -> [String: UInt64]
}

// MARK: - Diagnostics Protocol

/// A protocol that exposes diagnostic hooks for testing and instrumentation.
///
/// This allows tests to inject mock bridges or pre-canned token streams
/// without needing real hardware or a loaded model. Production code uses
/// the default implementation which delegates to the real engine.
///
/// Usage in tests:
/// ```swift
/// class MockOrchestrator: InferenceEngineDiagnostics {
///     var mockTokens: [EmittedToken] = [...]
///     func generateWithMockStream(...) -> AsyncStream<EmittedToken> { ... }
/// }
/// ```
protocol InferenceEngineDiagnostics: Sendable {
    /// The underlying inference engine being diagnosed.
    var engine: InferenceEngine { get async }

    /// Generate a token stream using a mock or pre-canned sequence.
    /// This is used in tests to verify eviction logic, token budgeting,
    /// and stream lifecycle without a physical device.
    ///
    /// - Parameters:
    ///   - mockTokens: A pre-defined sequence of tokens to emit.
    ///   - parameters: Generation parameters (used for stop token checks).
    /// - Returns: An AsyncStream that yields the mock tokens.
    func generateWithMockStream(
        mockTokens: [EmittedToken],
        parameters: GenerationParameters
    ) -> AsyncStream<EmittedToken>

    /// Scan a list of tokens for stop tokens and strip them.
    /// This is used to sanitize the assistant header tokens before
    /// injecting them into the KV cache via generateFromExistingContext().
    ///
    /// - Parameters:
    ///   - tokens: The token IDs to scan.
    ///   - stopTokenIDs: The set of stop token IDs to filter out.
    /// - Returns: The filtered token list with stop tokens removed.
    func stripStopTokens(
        from tokens: [Int32],
        stopTokenIDs: Set<Int32>
    ) -> [Int32]
}

/// Default implementation of InferenceEngineDiagnostics that provides
/// the stop token stripping logic (used in production and tests).
extension InferenceEngineDiagnostics {
    func stripStopTokens(
        from tokens: [Int32],
        stopTokenIDs: Set<Int32>
    ) -> [Int32] {
        tokens.filter { !stopTokenIDs.contains($0) }
    }

    /// Default mock stream implementation that simply yields the provided tokens.
    func generateWithMockStream(
        mockTokens: [EmittedToken],
        parameters: GenerationParameters
    ) -> AsyncStream<EmittedToken> {
        AsyncStream { continuation in
            Task {
                for token in mockTokens {
                    guard !Task.isCancelled else { break }
                    continuation.yield(token)
                    if token.isEndOfGeneration { break }
                }
                continuation.finish()
            }
        }
    }
}
