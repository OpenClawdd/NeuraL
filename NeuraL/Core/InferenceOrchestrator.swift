import Foundation

final class InferenceOrchestrator: InferenceEngine {
    private let bridge = LlamaCppBridge()
    var loadedModelMetadata: ModelMetadata?
    var maxContextLength: Int = 0

    func loadModel(path: String, config: ModelLoadConfiguration) async throws {
        try await bridge.loadModel(path: path, config: config)
        maxContextLength = config.contextLength
        loadedModelMetadata = ModelMetadata()
    }

    func generate(promptTokens: [Int32], parameters: GenerationParameters) -> AsyncThrowingStream<EmittedToken, Error> {
        bridge.generateStream(promptTokens: promptTokens, params: parameters)
    }

    func generateFromExistingContext(parameters: GenerationParameters) -> AsyncThrowingStream<EmittedToken, Error> {
        bridge.generateStreamFromExistingContext(parameters: parameters)
    }

    func unloadModel() {
        bridge.unloadModel()
    }
}
