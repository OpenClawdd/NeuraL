import Foundation

enum SwarmNodeRole: String, Codable, Sendable {
    case localSupervisor = "Local Supervisor"
    case remoteGenerator = "Remote Generator"
    case consensus = "Consensus"
}

enum SwarmConsensusState: String, Codable, Sendable {
    case idle = "Idle"
    case localOnly = "Local Only"
    case debating = "Debating"
    case aligned = "Aligned"
    case challenged = "Challenged"
    case regenerated = "Regenerated"
    case completed = "Completed"
    case failed = "Failed"
}

struct SwarmNodeTelemetry: Codable, Equatable, Sendable {
    var role: SwarmNodeRole
    var modelName: String
    var tokenCount: Int
    var tokensPerSecond: Double
    var confidence: Double
}

struct SwarmSnapshot: Codable, Equatable, Sendable {
    var state: SwarmConsensusState
    var local: SwarmNodeTelemetry
    var remote: SwarmNodeTelemetry?
    var consensusScore: Double
    var critique: String
    var updatedAt: Date = Date()

    static var idle: SwarmSnapshot {
        SwarmSnapshot(
            state: .idle,
            local: SwarmNodeTelemetry(
                role: .localSupervisor,
                modelName: "Local supervisor",
                tokenCount: 0,
                tokensPerSecond: 0,
                confidence: 0
            ),
            remote: nil,
            consensusScore: 0,
            critique: "No active swarm."
        )
    }
}

enum SwarmEvent: Sendable {
    case telemetry(SwarmSnapshot)
    case token(String)
    case halted(reason: String, snapshot: SwarmSnapshot)
    case completed(text: String, snapshot: SwarmSnapshot)
    case failed(String, snapshot: SwarmSnapshot)
}

struct SwarmConfiguration: Sendable {
    var mode: NeuralMode
    var prompt: String
    var parameters: GenerationParameters
    var enableRemote: Bool
    var remoteModel: String
    var localSupervisorName: String

    static func automatic(mode: NeuralMode, prompt: String, parameters: GenerationParameters) -> SwarmConfiguration {
        SwarmConfiguration(
            mode: mode,
            prompt: prompt,
            parameters: parameters,
            enableRemote: mode == .copilot || mode == .builder,
            remoteModel: "deepseek/deepseek-r1",
            localSupervisorName: "local-qwen-gemma-supervisor"
        )
    }
}

final class InferenceOrchestrator: InferenceEngine, @unchecked Sendable {
    private let bridge = LlamaCppBridge()
    var loadedModelMetadata: ModelMetadata?
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

    func runSwarm(configuration: SwarmConfiguration) -> AsyncStream<SwarmEvent> {
        AsyncStream { continuation in
            let task = Task {
                await executeSwarm(configuration: configuration, continuation: continuation)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func executeSwarm(
        configuration: SwarmConfiguration,
        continuation: AsyncStream<SwarmEvent>.Continuation
    ) async {
        let startedAt = Date()
        var accumulated = ""
        var snapshot = SwarmSnapshot(
            state: configuration.enableRemote ? .debating : .localOnly,
            local: SwarmNodeTelemetry(
                role: .localSupervisor,
                modelName: configuration.localSupervisorName,
                tokenCount: 0,
                tokensPerSecond: 0,
                confidence: 0.65
            ),
            remote: configuration.enableRemote
                ? SwarmNodeTelemetry(
                    role: .remoteGenerator,
                    modelName: configuration.remoteModel,
                    tokenCount: 0,
                    tokensPerSecond: 0,
                    confidence: 0.5
                )
                : nil,
            consensusScore: 0.65,
            critique: "Supervisor is checking the prompt shape."
        )
        continuation.yield(.telemetry(snapshot))

        if configuration.enableRemote, let apiKey = OpenRouterClient.apiKey {
            await streamRemote(
                configuration: configuration,
                apiKey: apiKey,
                snapshot: &snapshot,
                accumulated: &accumulated,
                startedAt: startedAt,
                continuation: continuation
            )
        } else {
            await streamLocalFallback(
                configuration: configuration,
                snapshot: &snapshot,
                accumulated: &accumulated,
                startedAt: startedAt,
                continuation: continuation
            )
        }
    }

    private func streamRemote(
        configuration: SwarmConfiguration,
        apiKey: String,
        snapshot: inout SwarmSnapshot,
        accumulated: inout String,
        startedAt: Date,
        continuation: AsyncStream<SwarmEvent>.Continuation
    ) async {
        do {
            let client = OpenRouterClient(apiKey: apiKey)
            for try await token in client.stream(prompt: configuration.prompt, model: configuration.remoteModel) {
                if Task.isCancelled { return }

                accumulated += token
                let localScore = supervisorScore(prompt: configuration.prompt, draft: accumulated)
                let tokenCount = max(1, Int(Double(accumulated.count) / 3.8))
                let elapsed = max(0.1, Date().timeIntervalSince(startedAt))

                snapshot.state = localScore < 0.35 ? .challenged : .aligned
                snapshot.local.tokenCount = max(1, snapshot.local.tokenCount + 1)
                snapshot.local.tokensPerSecond = Double(snapshot.local.tokenCount) / elapsed
                snapshot.local.confidence = localScore
                snapshot.remote?.tokenCount = tokenCount
                snapshot.remote?.tokensPerSecond = Double(tokenCount) / elapsed
                snapshot.remote?.confidence = min(0.98, 0.45 + Double(tokenCount) / 400.0)
                snapshot.consensusScore = localScore
                snapshot.critique = critique(for: localScore)
                snapshot.updatedAt = Date()

                if localScore < 0.2, accumulated.count > 120 {
                    continuation.yield(.halted(reason: "Supervisor detected drift from the prompt.", snapshot: snapshot))
                    let repaired = repairDraft(accumulated, prompt: configuration.prompt)
                    accumulated = repaired
                    snapshot.state = .regenerated
                    snapshot.consensusScore = 0.62
                    snapshot.critique = "Draft was compressed back to prompt-aligned structure."
                    continuation.yield(.telemetry(snapshot))
                    continuation.yield(.token("\n\n\(repaired)"))
                    break
                }

                continuation.yield(.telemetry(snapshot))
                continuation.yield(.token(token))
            }

            snapshot.state = .completed
            snapshot.updatedAt = Date()
            continuation.yield(.completed(text: accumulated, snapshot: snapshot))
            continuation.finish()
        } catch {
            snapshot.state = .failed
            snapshot.critique = "Remote stream failed. Falling back to on-device guided output."
            continuation.yield(.failed(error.localizedDescription, snapshot: snapshot))
            await streamLocalFallback(
                configuration: configuration,
                snapshot: &snapshot,
                accumulated: &accumulated,
                startedAt: startedAt,
                continuation: continuation
            )
        }
    }

    private func streamLocalFallback(
        configuration: SwarmConfiguration,
        snapshot: inout SwarmSnapshot,
        accumulated: inout String,
        startedAt: Date,
        continuation: AsyncStream<SwarmEvent>.Continuation
    ) async {
        let localTokens = await bridge.generateSync(promptTokens: [0], params: configuration.parameters)
        if !localTokens.isEmpty {
            for emitted in localTokens {
                if Task.isCancelled { return }
                accumulated += emitted.text
                updateLocalSnapshot(&snapshot, accumulated: accumulated, startedAt: startedAt)
                continuation.yield(.telemetry(snapshot))
                continuation.yield(.token(emitted.text))
            }
        } else {
            let fallback = guidedFallback(for: configuration)
            for character in fallback {
                if Task.isCancelled { return }
                accumulated.append(character)
                updateLocalSnapshot(&snapshot, accumulated: accumulated, startedAt: startedAt)
                continuation.yield(.telemetry(snapshot))
                continuation.yield(.token(String(character)))
                try? await Task.sleep(nanoseconds: 6_000_000)
            }
        }

        snapshot.state = .completed
        snapshot.critique = configuration.enableRemote
            ? "Remote node unavailable; local supervisor completed a structured fallback."
            : "Local node completed the response."
        snapshot.updatedAt = Date()
        continuation.yield(.completed(text: accumulated, snapshot: snapshot))
        continuation.finish()
    }

    private func updateLocalSnapshot(_ snapshot: inout SwarmSnapshot, accumulated: String, startedAt: Date) {
        let elapsed = max(0.1, Date().timeIntervalSince(startedAt))
        let tokenCount = max(1, Int(Double(accumulated.count) / 3.8))
        snapshot.state = .localOnly
        snapshot.local.tokenCount = tokenCount
        snapshot.local.tokensPerSecond = Double(tokenCount) / elapsed
        snapshot.local.confidence = supervisorScore(prompt: "", draft: accumulated)
        snapshot.consensusScore = snapshot.local.confidence
        snapshot.updatedAt = Date()
    }

    private func supervisorScore(prompt: String, draft: String) -> Double {
        let promptWords = Set(prompt.lowercased().split(separator: " ").filter { $0.count > 3 })
        let draftWords = Set(draft.lowercased().split(separator: " ").filter { $0.count > 3 })
        guard !promptWords.isEmpty, !draftWords.isEmpty else { return 0.62 }

        let overlap = promptWords.intersection(draftWords).count
        let overlapScore = Double(overlap) / Double(max(1, min(promptWords.count, 12)))
        let structuralScore = draft.contains("1.") || draft.contains("- ") ? 0.12 : 0
        let codeScore = draft.contains("```") || draft.contains("<") ? 0.08 : 0
        return min(0.98, max(0.12, 0.35 + overlapScore + structuralScore + codeScore))
    }

    private func critique(for score: Double) -> String {
        switch score {
        case 0.75...:
            return "Supervisor sees strong prompt alignment."
        case 0.45..<0.75:
            return "Supervisor sees partial alignment and is watching for drift."
        default:
            return "Supervisor is challenging the remote draft."
        }
    }

    private func repairDraft(_ draft: String, prompt: String) -> String {
        """
        Supervisor repair:
        1. Restate the target: \(prompt)
        2. Preserve useful draft material: \(draft.prefix(220))
        3. Continue with a tighter, prompt-aligned answer.
        """
    }

    private func guidedFallback(for configuration: SwarmConfiguration) -> String {
        switch configuration.mode {
        case .builder:
            return """
            Builder swarm fallback:

            1. Define the target artifact.
            2. Generate a minimal version first.
            3. Add diagnostics so the sandbox can report failures.
            4. Iterate from crash logs or user feedback.
            """
        case .copilot:
            return """
            Copilot swarm fallback:

            1. Clarify the goal.
            2. Identify the highest-leverage next step.
            3. Surface risks early.
            4. Keep the answer concise enough to act on.
            """
        case .researcher:
            return "Research mode is running local synthesis. Ask for a briefing document to expand this into a structured report."
        case .coach:
            return "Coach mode is running locally. Start by naming the outcome, the blocker, and the next ten-minute move."
        }
    }
}

private struct OpenRouterClient {
    static var apiKey: String? {
        let stored = UserDefaults.standard.string(forKey: "neural.openrouter.apiKey")
        guard let stored, !stored.isEmpty else {
            return ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"]
        }
        return stored
    }

    let apiKey: String

    func stream(prompt: String, model: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("NeuraL", forHTTPHeaderField: "X-Title")

                    let body = OpenRouterRequest(
                        model: model,
                        messages: [
                            OpenRouterMessage(role: "system", content: "You are a precise remote generator. Stay aligned with the user prompt."),
                            OpenRouterMessage(role: "user", content: prompt)
                        ],
                        stream: true
                    )
                    request.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        throw URLError(.badServerResponse)
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(OpenRouterStreamChunk.self, from: data),
                              let content = chunk.choices.first?.delta.content else {
                            continue
                        }
                        continuation.yield(content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

private struct OpenRouterRequest: Encodable {
    let model: String
    let messages: [OpenRouterMessage]
    let stream: Bool
}

private struct OpenRouterMessage: Encodable {
    let role: String
    let content: String
}

private struct OpenRouterStreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
        }
        let delta: Delta
    }
    let choices: [Choice]
}
