import Foundation

public struct ModelMetadata: Sendable {
    public let architecture: String = ""
    public let layerCount: Int = 0
    public let embeddingDimension: Int = 0
    public let vocabularySize: Int = 0
    public let trainingContextLength: Int = 0
    public let fileSize: UInt64 = 0
    public let quantization: String = ""
    public let estimatedMemoryFootprint: UInt64 = 0
}
public struct ModelLoadConfiguration: Sendable {
    public let contextLength: Int = 2048
    public let gpuLayers: Int = 99
    public let useMmap: Bool = true
    public let batchSize: Int = 512
    public static let `default` = ModelLoadConfiguration()
}
public struct GenerationParameters: Sendable {
    public let maxTokens: Int = 512
    public let temperature: Float = 0.7
    public let topP: Float = 0.9
    public let topK: Int32 = 40
    public let repeatPenalty: Float = 1.1
    public let repeatWindow: Int = 64
    public let stopTokens: [String] = []
    public let seed: UInt32? = nil
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
public protocol InferenceEngine: Sendable {
    var loadedModelMetadata: ModelMetadata? { get }
    var maxContextLength: Int { get }
    func loadModel(path: String, config: ModelLoadConfiguration) async throws
    func generate(promptTokens: [Int32], parameters: GenerationParameters) -> AsyncStream<EmittedToken>
    func generateFromExistingContext(parameters: GenerationParameters) -> AsyncStream<EmittedToken>
    func unloadModel()
}
