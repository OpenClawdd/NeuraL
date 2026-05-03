import Foundation

// MARK: - Core Types

public struct ModelMetadata: Sendable {
    public var architecture: String = ""
    public var layerCount: Int = 0
    public var embeddingDimension: Int = 0
    public var vocabularySize: Int = 0
    public var trainingContextLength: Int = 0
    public var fileSize: UInt64 = 0
    public var quantization: String = ""
    public var estimatedMemoryFootprint: UInt64 = 0
}

public struct ModelLoadConfiguration: Sendable {
    public var contextLength: Int = 2048
    public var gpuLayers: Int = 99
    public var useMmap: Bool = true
    public var batchSize: Int = 512
    public static let `default` = ModelLoadConfiguration()
}

public struct GenerationParameters: Sendable {
    public var maxTokens: Int = 512
    public var temperature: Float = 0.7
    public var topP: Float = 0.9
    public var topK: Int32 = 40
    public var repeatPenalty: Float = 1.1
    public var repeatWindow: Int = 64
    public var stopTokens: [String] = []
    public var seed: UInt32? = nil
    public static let `default` = GenerationParameters()
}

public struct EmittedToken: Sendable {
    public let text: String
    public let tokenID: Int32
    public let isEndOfGeneration: Bool
    public let cumulativeTokenCount: Int
    public let elapsedSeconds: TimeInterval
    public let probability: Float
}

public enum InferenceError: Error {
    case modelNotFound, modelCorrupt, insufficientMemory, unsupportedArchitecture,
         contextInvalidated, generationLimitExceeded, threadingViolation,
         contextSizeMismatch
    case backendInitializationFailed(String)
}

// MARK: - Engine Protocol

public protocol InferenceEngine: Sendable {
    var loadedModelMetadata: ModelMetadata? { get }
    var maxContextLength: Int { get }
    func loadModel(path: String, config: ModelLoadConfiguration) async throws
    func generate(promptTokens: [Int32], parameters: GenerationParameters) async -> [EmittedToken]
    func generateFromExistingContext(parameters: GenerationParameters) async -> [EmittedToken]
    func unloadModel()
}
