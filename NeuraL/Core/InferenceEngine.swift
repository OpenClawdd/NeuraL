import Foundation

public protocol InferenceEngine: Sendable {
    var loadedModelMetadata: ModelMetadata? { get }
    var maxContextLength: Int { get }
    func loadModel(path: String, config: ModelLoadConfiguration) async throws
    func generate(promptTokens: [Int32], parameters: GenerationParameters) async -> [EmittedToken]
    func generateFromExistingContext(parameters: GenerationParameters) async -> [EmittedToken]
    func unloadModel()
}
