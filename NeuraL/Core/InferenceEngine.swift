import Foundation

public struct ModelMetadata: Sendable {
    public let architecture: String
    public let layerCount: Int
    public let embeddingDimension: Int
    public let vocabularySize: Int
    public let trainingContextLength: Int
    public let fileSize: UInt64
    public let quantization: String
    public let estimatedMemoryFootprint: UInt64
    init(architecture: String = "", layerCount: Int = 0, embeddingDimension: Int = 0, vocabularySize: Int = 0, trainingContextLength: Int = 0, fileSize: UInt64 = 0, quantization: String = "", estimatedMemoryFootprint: UInt64 = 0) {
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

public struct ModelLoadConfiguration: Sendable {
    public let contextLength: Int
    public let gpuLayers: Int
    public let useMmap: Bool
    public let batchSize: Int
    static var `default`: ModelLoadConfiguration { ModelLoadConfiguration(contextLength: 2048, gpuLayers: 99, useMmap: true, batchSize: 512) }
}

public struct GenerationParameters: Sendable {
    public let maxTokens: Int
    public let temperature: Float
    public let topP: Float
    public let topK: Int32
    public let repeatPenalty: Float
    public let repeatWindow: Int
    public let stopTokens: [String]
    public let seed: UInt32?
    static var `default`: GenerationParameters { GenerationParameters(maxTokens: 512, temperature: 0.7, topP: 0.9, topK: 40, repeatPenalty: 1.1, repeatWindow: 64, stopTokens: [], seed: nil) }
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
    case modelNotFound
    case modelCorrupt
    case insufficientMemory
    case unsupportedArchitecture
    case contextInvalidated
    case generationLimitExceeded
    case threadingViolation
    case contextSizeMismatch
    case backendInitializationFailed(String)
}

public protocol InferenceEngine: Sendable {
    var loadedModelMetadata: ModelMetadata? { get }
    var maxContextLength: Int { get }
    func loadModel(path: String, config: ModelLoadConfiguration) async throws
    func generate(promptTokens: [Int32], parameters: GenerationParameters) -> AsyncThrowingStream<EmittedToken, Error>
    func generateFromExistingContext(parameters: GenerationParameters) -> AsyncThrowingStream<EmittedToken, Error>
    func resetContext()
    func unloadModel()
    func memoryStatistics() -> [String: Any]
}
