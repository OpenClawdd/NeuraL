import Foundation
actor ModelLoader {
    let bridge = LlamaCppBridge()
    func load(path: String, config: ModelLoadConfiguration) async throws -> ModelMetadata {
        try await bridge.loadModel(path: path, config: config)
        return ModelMetadata()
    }
}
