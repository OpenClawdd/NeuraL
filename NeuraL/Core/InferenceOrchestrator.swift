import Foundation

actor InferenceOrchestrator {
    var loadedModelMetadata: ModelMetadata?
    var maxContextLength: Int { loadedModelMetadata?.trainingContextLength ?? 2048 }

    func loadModel(path: String, config: ModelLoadConfiguration) async throws {
        loadedModelMetadata = ModelMetadata(architecture: "local", trainingContextLength: config.contextLength, quantization: "local")
    }

    func generate(promptTokens: [Int32], parameters: GenerationParameters) -> AsyncThrowingStream<EmittedToken, Error> {
        stream(text: "<think>Tracing reasoning for local response.</think>Local-only generation is active.")
    }

    func generateFromExistingContext(parameters: GenerationParameters) -> AsyncThrowingStream<EmittedToken, Error> {
        stream(text: "Local continuation complete.")
    }

    func resetContext() {}
    func unloadModel() { loadedModelMetadata = nil }
    func memoryStatistics() -> [String: Any] { [:] }

    private func stream(text: String) -> AsyncThrowingStream<EmittedToken, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let chars = Array(text)
                for (idx, ch) in chars.enumerated() {
                    continuation.yield(EmittedToken(text: String(ch), tokenID: Int32(idx), isEndOfGeneration: false, cumulativeTokenCount: idx + 1, elapsedSeconds: 0, probability: 1))
                }
                continuation.yield(EmittedToken(text: "", tokenID: 0, isEndOfGeneration: true, cumulativeTokenCount: chars.count, elapsedSeconds: 0, probability: 1))
                continuation.finish()
            }
        }
    }
}
