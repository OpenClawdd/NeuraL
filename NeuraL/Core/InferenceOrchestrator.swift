import Foundation
actor InferenceOrchestrator: InferenceEngine     case modelNotFound
e = LlamaCppBridge()
    var loadedModelMetadata: ModelMetadata? = nil
    var maxContextLength: Int { Int(bridge.maxContextLength) }

    func loadModel(path: String, config: ModelLoadConfiguration) async throws {
        try await bridge.loadModel(path: path, config: config)
        loadedModelMetadata = bridge.getModelMetadata()
    }

    func generate(promptTokens: [Int32], parameters: GenerationParameters) -> AsyncThrowingStream<EmittedToken, Error> {
        bridge.generateStream(promp    func generateFromExistingContext(parameters: GenerationParameteFromExistingContext(parameters: GenerationParameters) -> AsyncThrowingStream<EmittedToken, Error> {
        bridge.generateStreamFromExistingContext(parameters: parameters)
    }

    func resetContext() { bridge.resetContext() }
    func unloadModel() { bridge.unloadModel() }
    func memoryStatistics() -> [String: Any] { bridge.memoryStatistics() }
}
