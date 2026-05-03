import Foundation
actor ModelLoader {
    let bridge = LlamaCppBridge()
    func load
    func load config: ModelLoadConfiguration) async throws -> ModelMetadata {
        try await bridge.loadModel(path: path, config: config)
        return bridge.getModelMetadata()
    }
}
