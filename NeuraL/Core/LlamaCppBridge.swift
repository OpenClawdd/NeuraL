import Foundation
import os

actor LlamaCppBridge {
    typealias llama_token = Int32
    private var model: OpaquePointer?
    private var context: OpaquePointer?

    func loadModel(path: String, config: ModelLoadConfiguration) throws {
        var mparams = llama_model_default_params()
        mparams.n_gpu_layers = Int32(config.gpuLayers)
        mparams.use_mmap = config.useMmap
        guard let m = llama_model_load_from_file(path, mparams) else { throw InferenceError.modelNotFound }
        self.model = m

        var cparams = llama_context_default_params()
        cparams.n_ctx = UInt32(config.contextLength)
        cparams.n_batch = UInt32(config.batchSize)
        guard let ctx = llama_init_from_model(m, cparams) else { throw InferenceError.contextInvalidated }
        self.context = ctx
    }

    var contextLength: Int32 { context != nil ? llama_n_ctx(context!) : 0 }
    var maxContextLength: Int32 { contextLength }

    func tokenize(text: String, addBOS: Bool, special: Bool) -> [llama_token] {
        guard let model else { return [] }
        let vocab = llama_model_get_vocab(model)
        let cText = text.cString(using: .utf8)!
        let tokens = llama_tokenize(vocab, cText, addBOS, special)
        var result: [llama_token] = []
        for i in 0..<tokens.size { result.append(tokens.data[Int(i)]) }
        return result
    }

    func processPrompt(tokens: [llama_token]) {
        guard let ctx = context else { return }
        var t = tokens
        let batch = llama_batch_get_one(&t, Int32(tokens.count))
        llama_decode(ctx, batch)
    }

    func generateStream(promptTokens: [llama_token], params: GenerationParameters) -> AsyncThrowingStream<EmittedToken, Error> {
        AsyncThrowingStream { continuation in
            guard let model = self.model, let ctx = self.context else {
                continuation.finish(throwing: InferenceError.contextInvalidated)
                return
            }
            // process prompt
            self.processPrompt(tokens: promptTokens)

            let vocab = llama_model_get_vocab(model)
            var sparams = llama_sampler_chain_default_params()
            sparams.temp = params.temperature
            sparams.top_k = params.topK
            sparams.top_p = params.topP
            let chain = llama_sampler_chain_init(&sparams)
            llama_sampler_chain_add(chain, llama_sampler_init_temp(params.temperature))
            llama_sampler_chain_add(chain, llama_sampler_init_top_k(params.topK))
            llama_sampler_chain_add(chain, llama_sampler_init_top_p(params.topP, 1))
            llama_sampler_chain_add(chain, llama_sampler_init_softmax())
            if let seed = params.seed { llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32(seed))) }

            var count = 0
            let start = Date()
            for _ in 0..<params.maxTokens {
                let token = llama_sampler_sample(chain, ctx, -1)
                if llama_vocab_is_eog(vocab, token) {
                    continuation.yield(EmittedToken(text: "", tokenID: token, isEndOfGeneration: true, cumulativeTokenCount: count, elapsedSeconds: Date().timeIntervalSince(start), probability: 1))
                    break
                }
                let str = String(cString: llama_token_to_str(vocab, token))
                continuation.yield(EmittedToken(text: str, tokenID: token, isEndOfGeneration: false, cumulativeTokenCount: count, elapsedSeconds: Date().timeIntervalSince(start), probability: 1))
                var one = [token]
                let batch = llama_batch_get_one(&one, 1)
                llama_decode(ctx, batch)
                count += 1
            }
            llama_sampler_free(chain)
            continuation.finish()
        }
    }

    func generateStreamFromExistingContext(parameters: GenerationParameters) -> AsyncThrowingStream<EmittedToken, Error> {
        AsyncThrowingStream { continuation in
            guard let model = self.model, let ctx = self.context else {
                continuation.finish(throwing: InferenceError.contextInvalidated)
                return
            }
            let vocab = llama_model_get_vocab(model)
            var sparams = llama_sampler_chain_default_params()
            sparams.temp = parameters.temperature
            sparams.top_k = parameters.topK
            sparams.top_p = parameters.topP
            let chain = llama_sampler_chain_init(&sparams)
            llama_sampler_chain_add(chain, llama_sampler_init_temp(parameters.temperature))
            llama_sampler_chain_add(chain, llama_sampler_init_top_k(parameters.topK))
            llama_sampler_chain_add(chain, llama_sampler_init_top_p(parameters.topP, 1))
            llama_sampler_chain_add(chain, llama_sampler_init_softmax())
            if let seed = parameters.seed { llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32(seed))) }

            var count = 0
            let start = Date()
            for _ in 0..<parameters.maxTokens {
                let token = llama_sampler_sample(chain, ctx, -1)
                if llama_vocab_is_eog(vocab, token) {
                    continuation.yield(EmittedToken(text: "", tokenID: token, isEndOfGeneration: true, cumulativeTokenCount: count, elapsedSeconds: Date().timeIntervalSince(start), probability: 1))
                    break
                }
                let str = String(cString: llama_token_to_str(vocab, token))
                continuation.yield(EmittedToken(text: str, tokenID: token, isEndOfGeneration: false, cumulativeTokenCount: count, elapsedSeconds: Date().timeIntervalSince(start), probability: 1))
                var one = [token]
                let batch = llama_batch_get_one(&one, 1)
                llama_decode(ctx, batch)
                count += 1
            }
            llama_sampler_free(chain)
            continuation.finish()
        }
    }

    func unloadModel() {
        if let ctx = context { llama_free(ctx); context = nil }
        if let model = model { llama_model_free(model); model = nil }
    }
}
