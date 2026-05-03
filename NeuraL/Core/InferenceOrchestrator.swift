import Foundation
actor InferenceOrchestrator: InferenceEngine {
    private let bridge = LlamaCppBridge()
    var loadedModelMetadata: ModelMetadata?
    var maxContextLength: Int { Int(bridge.maxContextLength) }

    func loadModel(path: String, config: ModelLoadConfiguration) async throws {
        try bridge.loadModel(path: path, config: config)
    }
    func generate(promptTokens: [Int32], parameters: GenerationParameters) -> AsyncThrowingStream<EmittedToken, Error> {
        bridge.generateStream(promptTokens: promptTokens, params: parameters)
    }
    func generateFromExistingContext(parameters: GenerationParameters) -> AsyncThrowingStream<EmittedToken, Error> {
        bridge.generateStreamFromExistingContext(parameters: parameters)
    }
    func unloadModel() { bridge.unloadModel() }
}
