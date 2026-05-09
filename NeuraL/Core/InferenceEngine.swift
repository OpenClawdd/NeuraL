import Foundation
import UIKit

// MARK: - Errors

enum InferenceError: LocalizedError, CustomStringConvertible, Equatable {
    case modelNotFound(path: String)
    case modelCorrupt(path: String, detail: String)
    case insufficientMemory(requiredBytes: UInt64, availableBytes: UInt64)
    case unsupportedArchitecture(arch: String)
    case contextInvalidated
    case generationLimitExceeded
    case threadingViolation(detail: String)
    case contextSizeMismatch(requested: Int, actual: Int)
    case backendInitializationFailed(detail: String)

    var description: String {
        switch self {
        case .modelNotFound(let path): return "Model not found at: \(path)"
        case .modelCorrupt(let path, let detail): return "Model file corrupt (\(detail)): \(path)"
        case .insufficientMemory(let required, let available): return "Insufficient memory: need \(required) bytes, have \(available) bytes"
        case .unsupportedArchitecture(let arch): return "Unsupported model architecture: \(arch)"
        case .contextInvalidated: return "Inference context was invalidated"
        case .generationLimitExceeded: return "Generation limit exceeded"
        case .threadingViolation(let detail): return "Threading violation: \(detail)"
        case .contextSizeMismatch(let requested, let actual): return "Context size mismatch: requested \(requested), got \(actual)"
        case .backendInitializationFailed(let detail): return "Backend initialization failed: \(detail)"
        }
    }

    var errorDescription: String? { description }
}

// MARK: - Model Configuration

struct MemoryBudget: Sendable, Equatable {
    let maxContextLength: Int
    let estimatedTotalBytes: UInt64
    let remainingFreeBytes: UInt64
    let gpuOffloadingRecommended: Bool
    let recommendedThreadCount: Int
    let thermalState: ProcessInfo.ThermalState

    var canLoad: Bool { remainingFreeBytes >= 200 * 1_048_576 }
}

struct ModelMetadata: Sendable, Equatable {
    let architecture: String
    let layerCount: Int
    let embeddingDimension: Int
    let vocabularySize: Int
    let trainingContextLength: Int
    let fileSize: UInt64
    let quantization: String
    let estimatedMemoryFootprint: UInt64

    init(
        architecture: String = "",
        layerCount: Int = 0,
        embeddingDimension: Int = 0,
        vocabularySize: Int = 0,
        trainingContextLength: Int = 0,
        fileSize: UInt64 = 0,
        quantization: String = "",
        estimatedMemoryFootprint: UInt64 = 0
    ) {
        self.architecture = architecture
        self.layerCount = layerCount
        self.embeddingDimension = embeddingDimension
        self.vocabularySize = vocabularySize
        self.trainingContextLength = trainingContextLength
        self.fileSize = fileSize
        self.quantization = quantization
        self.estimatedMemoryFootprint = estimatedMemoryFootprint
    }
}

struct ModelLoadConfiguration: Sendable, Equatable {
    let maxContextLength: Int
    let gpuLayerCount: Int
    let generationThreadCount: Int
    let batchThreadCount: Int
    let useMemoryMapping: Bool
    let batchSize: Int

    var contextLength: Int { maxContextLength }
    var gpuLayers: Int { gpuLayerCount == Int.max ? 99 : gpuLayerCount }
    var useMmap: Bool { useMemoryMapping }

    static let `default` = ModelLoadConfiguration(
        maxContextLength: 2048,
        gpuLayerCount: Int.max,
        generationThreadCount: 2,
        batchThreadCount: 4,
        useMemoryMapping: true,
        batchSize: 512
    )

    static let conservative = ModelLoadConfiguration(
        maxContextLength: 1024,
        gpuLayerCount: 0,
        generationThreadCount: 1,
        batchThreadCount: 2,
        useMemoryMapping: true,
        batchSize: 256
    )
}

struct GenerationParameters: Sendable, Equatable {
    let maxTokens: Int
    let temperature: Float
    let topP: Float
    let topK: Int32
    let repeatPenalty: Float
    let repeatPenaltyWindowSize: Int
    let stopTokens: [String]
    let seed: UInt64?

    var repeatWindow: Int { repeatPenaltyWindowSize }

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

    static let `default` = GenerationParameters.chat
}

// MARK: - Engine State / Tokens

enum EngineState: Sendable, CustomStringConvertible, Equatable {
    case idle
    case loading(progress: Float)
    case ready
    case generating
    case error(InferenceError)
    case unloading

    var description: String {
        switch self {
        case .idle: return "Idle"
        case .loading(let progress): return String(format: "Loading (%.0f%%)", progress * 100)
        case .ready: return "Ready"
        case .generating: return "Generating"
        case .error(let error): return "Error: \(error.description)"
        case .unloading: return "Unloading"
        }
    }
}

struct EmittedToken: Sendable, Equatable {
    let text: String
    let tokenID: Int
    let isEndOfGeneration: Bool
    let cumulativeTokenCount: Int
    let elapsedSeconds: Double
    let probability: Float?
}

// MARK: - Inference Protocols

protocol InferenceEngine: Sendable {
    var loadedModelMetadata: ModelMetadata? { get async }
    var maxContextLength: Int { get async }

    func loadModel(from modelURL: URL, configuration: ModelLoadConfiguration) async throws
    func unloadModel() async
    func generate(promptTokens: [Int32], parameters: GenerationParameters) async -> AsyncThrowingStream<EmittedToken, Error>
    func generateFromExistingContext(parameters: GenerationParameters) async -> AsyncThrowingStream<EmittedToken, Error>
    func resetContext() async
    func memoryStatistics() async -> [String: Any]
}

protocol InferenceEngineDiagnostics: Sendable {
    var engine: InferenceEngine { get async }

    func generateWithMockStream(
        mockTokens: [EmittedToken],
        parameters: GenerationParameters
    ) -> AsyncStream<EmittedToken>

    func stripStopTokens(from tokens: [Int32], stopTokenIDs: Set<Int32>) -> [Int32]
}

extension InferenceEngineDiagnostics {
    func stripStopTokens(from tokens: [Int32], stopTokenIDs: Set<Int32>) -> [Int32] {
        tokens.filter { !stopTokenIDs.contains($0) }
    }

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
