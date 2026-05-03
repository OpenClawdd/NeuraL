import Foundation

final class InferenceOrchestrator: InferenceEngine {
    private let bridge = LlamaCppBridge()
    nonisolated var loadedModelMetadata: ModelMetadata?
    var maxContextLength: Int = 0

    func loadModel(path: String, config: ModelLoadConfiguration) async throws {
        try await bridge.loadModel(path: path, config: config)
        maxContextLength = config.contextLength
        loadedModelMetadata = ModelMetadata()
    }

    func generate(promptTokens: [Int32], parameters: GenerationParameters) async -> [EmittedToken] {
        await bridge.generateSync(promptTokens: promptTokens, params: parameters)
    }

    func generateFromExistingContext(parameters: GenerationParameters) async -> [EmittedToken] {
        await bridge.generateSync(promptTokens: [], params: parameters)
    }

    func unloadModel() {
        Task { await bridge.unloadModel() }
    }
}

