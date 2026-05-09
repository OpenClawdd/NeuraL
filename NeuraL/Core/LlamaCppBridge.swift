import Foundation
import os

actor LlamaCppBridge {
    private struct RuntimeSnapshot: @unchecked Sendable {
        let model: OpaquePointer
        let context: OpaquePointer
    }

    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var sampler: UnsafeMutablePointer<llama_sampler>?

    init() {
        llama_backend_init()
    }

    deinit {
        if let ctx = context { llama_free(ctx) }
        if let model = model { llama_model_free(model) }
    }

    var contextLength: Int32 {
        guard let ctx = context else { return 0 }
        return Int32(llama_n_ctx(ctx))
    }

    var maxContextLength: Int32 { contextLength }

    func loadModel(path: String, config: ModelLoadConfiguration) throws {
        unloadModel()

        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = Int32(config.gpuLayers)
        modelParams.use_mmap = config.useMmap

        guard let m = llama_model_load_from_file(path, modelParams) else {
            throw InferenceError.modelNotFound(path: path)
        }
        self.model = m

        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = UInt32(config.contextLength)
        ctxParams.n_batch = UInt32(config.batchSize)
        ctxParams.n_threads = Int32(config.generationThreadCount)
        ctxParams.n_threads_batch = Int32(config.batchThreadCount)
        guard let ctx = llama_init_from_model(m, ctxParams) else {
            llama_model_free(m)
            self.model = nil
            throw InferenceError.contextInvalidated
        }
        self.context = ctx
    }

    func getModelMetadata() -> ModelMetadata {
        guard let m = model else { return ModelMetadata() }
        let vocab = llama_model_get_vocab(m)
        let nVocab = llama_vocab_n_tokens(vocab)
        var descriptionBuffer = [CChar](repeating: 0, count: 256)
        llama_model_desc(m, &descriptionBuffer, descriptionBuffer.count)
        let arch = String(cString: descriptionBuffer)
        return ModelMetadata(
            architecture: arch,
            layerCount: Int(llama_model_n_layer(m)),
            embeddingDimension: Int(llama_model_n_embd(m)),
            vocabularySize: Int(nVocab),
            trainingContextLength: Int(llama_model_n_ctx_train(m)),
            fileSize: 0,
            quantization: "",
            estimatedMemoryFootprint: 0
        )
    }

    func tokenize(text: String, addBOS: Bool, special: Bool) async throws -> [llama_token] {
        guard let m = model else { throw InferenceError.contextInvalidated }
        var tokens: [llama_token] = []
        let vocab = llama_model_get_vocab(m)
        return try text.withCString { cText in
            let textLength = Int32(text.utf8.count)
            let requiredCount = llama_tokenize(vocab, cText, textLength, nil, 0, addBOS, special)
            guard requiredCount != Int32.min else {
                throw InferenceError.contextInvalidated
            }

            let tokenCapacity = Int(abs(requiredCount))
            guard tokenCapacity > 0 else { return [] }

            var tokens = Array(repeating: llama_token(0), count: tokenCapacity)
            let writtenCount = llama_tokenize(
                vocab,
                cText,
                textLength,
                &tokens,
                Int32(tokens.count),
                addBOS,
                special
            )
            guard writtenCount >= 0 else {
                throw InferenceError.contextInvalidated
            }

            tokens.removeSubrange(Int(writtenCount)..<tokens.count)
            return tokens
        }
    }

    func processPrompt(tokens: [llama_token]) async throws {
        guard let ctx = context else { throw InferenceError.contextInvalidated }
        try Self.decodePrompt(tokens: tokens, context: ctx)
    }

    func generateStream(promptTokens: [llama_token], params: GenerationParameters) -> AsyncThrowingStream<EmittedToken, Error> {
        guard let snapshot = runtimeSnapshot() else {
            return Self.failureStream(InferenceError.contextInvalidated)
        }

        do {
            try Self.decodePrompt(tokens: promptTokens, context: snapshot.context)
        } catch {
            return Self.failureStream(error)
        }

        return Self.makeGenerationStream(snapshot: snapshot, params: params)
    }

    func generateStreamFromExistingContext(parameters: GenerationParameters) -> AsyncThrowingStream<EmittedToken, Error> {
        guard let snapshot = runtimeSnapshot() else {
            return Self.failureStream(InferenceError.contextInvalidated)
        }
        return Self.makeGenerationStream(snapshot: snapshot, params: parameters)
    }

    func resetContext() {}
    func clearKVCache() {}
    func evictOldestTokens(count: Int) {}

    func unloadModel() {
        if let ctx = context { llama_free(ctx) }
        if let model = model { llama_model_free(model) }
        context = nil
        model = nil
        sampler = nil
    }

    func memoryStatistics() -> [String: Any] { return [:] }

    private func runtimeSnapshot() -> RuntimeSnapshot? {
        guard let model, let context else { return nil }
        return RuntimeSnapshot(model: model, context: context)
    }

    private static func decodePrompt(tokens: [llama_token], context: OpaquePointer) throws {
        guard !tokens.isEmpty else { return }
        var mutableTokens = tokens
        let batch = llama_batch_get_one(&mutableTokens, Int32(tokens.count))
        if llama_decode(context, batch) != 0 {
            throw InferenceError.contextInvalidated
        }
    }

    private static func failureStream(_ error: Error) -> AsyncThrowingStream<EmittedToken, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }

    private static func makeGenerationStream(
        snapshot: RuntimeSnapshot,
        params: GenerationParameters
    ) -> AsyncThrowingStream<EmittedToken, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let vocab = llama_model_get_vocab(snapshot.model)
                let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())
                llama_sampler_chain_add(chain, llama_sampler_init_temp(params.temperature))
                llama_sampler_chain_add(chain, llama_sampler_init_top_k(params.topK))
                llama_sampler_chain_add(chain, llama_sampler_init_top_p(params.topP, 1))
                if let seed = params.seed {
                    llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32(truncatingIfNeeded: seed)))
                }

                var totalTokens = 0
                let startTime = Date()

                for _ in 0..<params.maxTokens {
                    guard !Task.isCancelled else { break }

                    let token = llama_sampler_sample(chain, snapshot.context, -1)
                    if llama_vocab_is_eog(vocab, token) {
                        continuation.yield(EmittedToken(
                            text: "",
                            tokenID: Int(token),
                            isEndOfGeneration: true,
                            cumulativeTokenCount: totalTokens,
                            elapsedSeconds: Date().timeIntervalSince(startTime),
                            probability: 1.0
                        ))
                        break
                    }

                    let text = String(cString: llama_vocab_get_text(vocab, token))
                    continuation.yield(EmittedToken(
                        text: text,
                        tokenID: Int(token),
                        isEndOfGeneration: false,
                        cumulativeTokenCount: totalTokens,
                        elapsedSeconds: Date().timeIntervalSince(startTime),
                        probability: 1.0
                    ))

                    var oneTokenArray = [token]
                    let oneToken = llama_batch_get_one(&oneTokenArray, 1)
                    llama_decode(snapshot.context, oneToken)
                    totalTokens += 1
                }

                llama_sampler_free(chain)
                continuation.finish()
            }
        }
    }
}
