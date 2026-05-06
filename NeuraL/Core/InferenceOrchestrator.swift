import Foundation

actor InferenceOrchestrator: InferenceEngine {
    private let bridge = LlamaCppBridge()
    private(set) var loadedModelMetadata: ModelMetadata?

    var maxContextLength: Int { loadedModelMetadata?.trainingContextLength ?? 0 }

    func loadModel(path: String, config: ModelLoadConfiguration) async throws {
        try await bridge.loadModel(path: path, config: config)
        loadedModelMetadata = await bridge.getModelMetadata()
    }

    func loadModel(from url: URL, configuration: ModelLoadConfiguration = .default) async throws {
        try await loadModel(path: url.path, config: configuration)
    }

    func tokenize(text: String, addBOS: Bool = true, special: Bool = true) async throws -> [Int32] {
        try await bridge.tokenize(text: text, addBOS: addBOS, special: special).map { Int32($0) }
    }

    func generate(promptTokens: [Int32], parameters: GenerationParameters) async -> AsyncThrowingStream<EmittedToken, Error> {
        guard loadedModelMetadata != nil else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: InferenceError.modelNotFound(path: "No model loaded"))
            }
        }
        return await bridge.generateStream(promptTokens: promptTokens, params: parameters)
    }

    func generateFromExistingContext(parameters: GenerationParameters) async -> AsyncThrowingStream<EmittedToken, Error> {
        guard loadedModelMetadata != nil else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: InferenceError.modelNotFound(path: "No model loaded"))
            }
        }
        return await bridge.generateStreamFromExistingContext(parameters: parameters)
    }

    func resetContext() async {
        await bridge.resetContext()
    }

    func unloadModel() async {
        await bridge.unloadModel()
        loadedModelMetadata = nil
    }

    func memoryStatistics() async -> [String: Any] {
        await bridge.memoryStatistics()
    }
}
