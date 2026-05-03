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

    func generate(promptTokens: [Int32], parameters: GenerationParameters) -> AsyncStream<EmittedToken> {
        let bridgeRef = bridge
        return AsyncStream { continuation in
            Task {
                let stream = await bridgeRef.generateStream(promptTokens: promptTokens, params: parameters)
                for await token in stream {
                    continuation.yield(token)
                }
                continuation.finish()
            }
        }
    }

    func generateFromExistingContext(parameters: GenerationParameters) -> AsyncStream<EmittedToken> {
        let bridgeRef = bridge
        return AsyncStream { continuation in
            Task {
                let stream = await bridgeRef.generateStreamFromExistingContext(parameters: parameters)
                for await token in stream {
                    continuation.yield(token)
                }
                continuation.finish()
            }
        }
    }

    func unloadModel() {
        Task { await bridge.unloadModel() }
    }
}
