import Foundation
import os
import llama

actor LlamaCppBridge {
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var sampler: UnsafeMutablePointer<llama_sampler>?

    var contextLength: Int32 {
        guard let ctx = context else { return 0 }
        return llama_n_ctx(ctx)
    }

    var maxContextLength: Int32 { contextLength }

    func loadModel(path: String, config: ModelLoadConfiguration) throws {
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = Int32(config.gpuLayers)
        modelParams.use_mmap = config.useMmap

        guard let m = llama_model_load_from_file(path, modelParams) else {
            throw InferenceError.modelNotFound
        }
        self.model = m

        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = UInt32(config.contextLength)
        ctxParams.n_batch = UInt32(config.batchSize)
        guard let ctx = llama_init_from_model(m, ctxParams) else {
            throw InferenceError.contextInvalidated
        }
        self.context = ctx
    }

    func getModelMetadata() -> ModelMetadata {
        guard let m = model else { return ModelMetadata() }
        let nVocab = llama_vocab_size(llama_model_get_vocab(m))
        let archCStr = llama_model_arch(m) ?? ""
        let arch = String(cString: archCStr)
        return ModelMetadata(architecture: arch, layerCount: Int(llama_model_n_layer(m)), embeddingDimension: Int(llama_model_n_embd(m)), vocabularySize: Int(nVocab), trainingContextLength: Int(llama_model_n_ctx_train(m)), fileSize: 0, quantization: "", estimatedMemoryFootprint: 0)
    }

    func tokenize(text: String, addBOS: Bool, special: Bool) async throws -> [llama_token] {
        guard let m = model else { return [] }
        var tokens: [llama_token] = []
        let vocab = llama_model_get_vocab(m)
        let cText = text.cString(using: .utf8)!
        let tokenList = llama_tokenize(vocab, cText, addBOS, special)
        for i in 0..<tokenList.size {
            tokens.append(tokenList.data[Int(i)])
        }
        return tokens
    }

    func processPrompt(tokens: [llama_token]) async throws {
        guard let ctx = context else { return }
        var t = tokens
        let batch = llama_batch_get_one(&t, Int32(tokens.count))
        if llama_decode(ctx, batch) != 0 {
            throw InferenceError.contextInvalidated
        }
    }

    func generateStream(promptTokens: [llama_token], params: GenerationParameters) -> AsyncThrowingStream<EmittedToken, Error> {
        AsyncThrowingStream { continuation in
            Task { [weak self] in
                guard let self = self, let ctx = self.context else {
                    continuation.finish(throwing: InferenceError.contextInvalidated)
                    return
                }
                // Process prompt
                do {
                    try await self.processPrompt(tokens: promptTokens)
                } catch {
                    continuation.finish(throwing: error)
                    return
                }

                // Set up sampler
                var chain = llama_sampler_chain_init(llama_model_get_vocab(self.model!))
                llama_sampler_chain_add(chain, llama_sampler_init_temp(params.temperature))
                llama_sampler_chain_add(chain, llama_sampler_init_top_k(params.topK))
                llama_sampler_chain_add(chain, llama_sampler_init_top_p(params.topP, 1))
                llama_sampler_chain_add(chain, llama_sampler_init_softmax())
                if let seed = params.seed {
                    llama_sampler_chain_add(chain, llama_sampler_init_dist(seed))
                }

                var totalTokens = 0
                let startTime = Date()
                for _ in 0..<params.maxTokens {
                    let token = llama_sampler_sample(chain, ctx, -1)
                    if llama_vocab_is_eog(llama_model_get_vocab(self.model!), token) {
                        continuation.yield(EmittedToken(text: "", tokenID: token, isEndOfGeneration: true, cumulativeTokenCount: totalTokens, elapsedSeconds: Date().timeIntervalSince(startTime), probability: 1.0))
                        break
                    }
                    let text = String(cString: llama_token_to_str(llama_model_get_vocab(self.model!), token))
                    continuation.yield(EmittedToken(text: text, tokenID: token, isEndOfGeneration: false, cumulativeTokenCount: totalTokens, elapsedSeconds: Date().timeIntervalSince(startTime), probability: 1.0))
                    let oneToken = llama_batch_get_one(&[token], 1)
                    llama_decode(ctx, oneToken)
                    totalTokens += 1
                }
                llama_sampler_free(chain)
                continuation.finish()
            }
        }
    }

    func generateStreamFromExistingContext(parameters: GenerationParameters) -> AsyncThrowingStream<EmittedToken, Error> {
        AsyncThrowingStream { continuation in
            Task { [weak self] in
                guard let self = self, let ctx = self.context else {
                    continuation.finish(throwing: InferenceError.contextInvalidated)
                    return
                }
                // Start generation loop without prompt processing
                var chain = llama_sampler_chain_init(llama_model_get_vocab(self.model!))
                llama_sampler_chain_add(chain, llama_sampler_init_temp(params.temperature))
                llama_sampler_chain_add(chain, llama_sampler_init_top_k(params.topK))
                llama_sampler_chain_add(chain, llama_sampler_init_top_p(params.topP, 1))
                llama_sampler_chain_add(chain, llama_sampler_init_softmax())
                if let seed = params.seed {
                    llama_sampler_chain_add(chain, llama_sampler_init_dist(seed))
                }
                var totalTokens = 0
                let startTime = Date()
                for _ in 0..<params.maxTokens {
                    let token = llama_sampler_sample(chain, ctx, -1)
                    if llama_vocab_is_eog(llama_model_get_vocab(self.model!), token) {
                        continuation.yield(EmittedToken(text: "", tokenID: token, isEndOfGeneration: true, cumulativeTokenCount: totalTokens, elapsedSeconds: Date().timeIntervalSince(startTime), probability: 1.0))
                        break
                    }
                    let text = String(cString: llama_token_to_str(llama_model_get_vocab(self.model!), token))
                    continuation.yield(EmittedToken(text: text, tokenID: token, isEndOfGeneration: false, cumulativeTokenCount: totalTokens, elapsedSeconds: Date().timeIntervalSince(startTime), probability: 1.0))
                    let oneToken = llama_batch_get_one(&[token], 1)
                    llama_decode(ctx, oneToken)
                    totalTokens += 1
                }
                llama_sampler_free(chain)
                continuation.finish()
            }
        }
    }

    func resetContext() {}
    func clearKVCache() {}
    func evictOldestTokens(count: Int) {}
    func unloadModel() {
        if let ctx = context { llama_free(ctx) }
        if let model = model { llama_model_free(model) }
    }
    func memoryStatistics() -> [String: Any] { return [:] }
}
