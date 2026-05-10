import Foundation

actor InferenceOrchestrator {
    var loadedModelMetadata: ModelMetadata?
    var maxContextLength: Int { loadedModelMetadata?.trainingContextLength ?? 2048 }

    let bridge = LlamaCppBridge()

    func loadModel(path: String, config: ModelLoadConfiguration) async throws {
        try await bridge.loadModel(path: path, config: config)
        loadedModelMetadata = await bridge.getModelMetadata()
    }

    func generate(promptTokens: [Int32], parameters: GenerationParameters) async -> AsyncThrowingStream<EmittedToken, Error> {
        return await bridge.generateStream(promptTokens: promptTokens, params: parameters)
    }

    func generateFromExistingContext(parameters: GenerationParameters) async -> AsyncThrowingStream<EmittedToken, Error> {
        return await bridge.generateStreamFromExistingContext(parameters: parameters)
    }

    func tokenize(text: String, addBOS: Bool = true, special: Bool = false) async throws -> [Int32] {
        return try await bridge.tokenize(text: text, addBOS: addBOS, special: special)
    }

    func resetContext() async { await bridge.resetContext() }
    
    func unloadModel() async {
        await bridge.unloadModel()
        loadedModelMetadata = nil
    }
    
    func memoryStatistics() async -> [String: Any] { await bridge.memoryStatistics() }
}
