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
        let bridgeRef = bridge
        return AsyncThrowingStream { continuation in
            Task {
                let stream = await bridgeRef.generateStream(promptTokens: promptTokens, params: parameters)
                do {
                    for try await token in stream {
                        continuation.yield(token)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func generateFromExistingContext(parameters: GenerationParameters) -> AsyncThrowingStream<EmittedToken, Error> {
        let bridgeRef = bridge
        return AsyncThrowingStream { continuation in
            Task {
                let stream = await bridgeRef.generateStreamFromExistingContext(parameters: parameters)
                do {
                    for try await token in stream {
                        continuation.yield(token)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func unloadModel() {
        Task { await bridge.unloadModel() }
    }
}
