import SwiftUI
import UniformTypeIdentifiers

enum NeuralMode: String, CaseIterable, Identifiable {
    case copilot = "Copilot"
    case researcher = "Research"
    case builder = "Builder"
    case coach = "Coach"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .copilot: return "sparkles"
        case .researcher: return "doc.text.magnifyingglass"
        case .builder: return "hammer"
        case .coach: return "figure.mind.and.body"
        }
    }

    var tint: Color {
        switch self {
        case .copilot: return .blue
        case .researcher: return .teal
        case .builder: return .orange
        case .coach: return .green
        }
    }

    var behavior: String {
        switch self {
        case .copilot:
            return "balanced, practical help with crisp next steps"
        case .researcher:
            return "careful synthesis, assumptions, gaps, and source-minded structure"
        case .builder:
            return "implementation-focused answers with decisions and tradeoffs"
        case .coach:
            return "guided thinking, reflection, and momentum-building prompts"
        }
    }

    var starterPrompts: [String] {
        switch self {
        case .copilot:
            return [
                "Turn this rough idea into a clear plan",
                "Help me make a decision from these options",
                "Summarize this and tell me what matters"
            ]
        case .researcher:
            return [
                "Create a research brief for this topic",
                "Find the hidden assumptions in this argument",
                "Compare these options with a scoring matrix"
            ]
        case .builder:
            return [
                "Design the MVP feature set for this app",
                "Break this into tickets I can ship",
                "Review this implementation plan for risks"
            ]
        case .coach:
            return [
                "Help me untangle what I am trying to say",
                "Ask me questions until the next step is obvious",
                "Turn this goal into a focused 30-minute sprint"
            ]
        }
    }
}

struct NeuralPulse: Equatable {
    var intent: String
    var momentum: String
    var nextMoves: [String]
    var caution: String
    var consensus: String
    var localTokenRate: Double
    var remoteTokenRate: Double?
    var confidence: Double
    var sandboxStatus: String
    var shadowInsight: String?
}

@MainActor
final class ChatState: ObservableObject {
    static let defaultSystemPrompt = "You are NeuraL, a private on-device assistant. Be clear, useful, and proactive. Match the selected mode and surface next steps when helpful."

    @Published var messages: [ChatMessage]
    @Published var isGenerating = false
    @Published var streamingText = ""
    @Published var selectedMode: NeuralMode = .copilot {
        didSet { refreshPulse() }
    }
    @Published var pinnedMessages: Set<UUID> = []
    @Published var conversation = Conversation(systemPrompt: ChatState.defaultSystemPrompt)
    @Published var contextTokensUsed: Int = 0
    @Published var pulse = NeuralPulse(
        intent: "Waiting for a direction",
        momentum: "Ready",
        nextMoves: ["Pick a mode", "Use a starter prompt", "Drop in your goal"],
        caution: "Private by default",
        consensus: "Idle",
        localTokenRate: 0,
        remoteTokenRate: nil,
        confidence: 0,
        sandboxStatus: "No artifact mounted",
        shadowInsight: nil
    )
    @Published var swarmSnapshot = SwarmSnapshot.idle {
        didSet { refreshPulse() }
    }
    @Published var shadowInsights: [ShadowInsight] = [] {
        didSet { refreshPulse() }
    }

    let orchestrator = InferenceOrchestrator()
    private var generationTask: Task<Void, Never>?
    private let documentImporter = LightweightDocumentImporter()
    private let shadowMemory = ShadowMemorySynthesizer()

    var defaultSystemPrompt: String { Self.defaultSystemPrompt }

    init() {
        let welcome = ChatMessage.assistantMessage("Welcome to NeuraL. Choose a mode, drop in a task, and I will keep a live Pulse of what you are trying to do plus the next best moves.")
        self.messages = [welcome]
        self.conversation.messages.append(welcome)
        refreshTokenBudget()
    }

    var modelMetadata: ModelMetadata? { orchestrator.loadedModelMetadata }
    var engineState: String { isGenerating ? "generating" : "idle" }

    var visibleMessages: [ChatMessage] {
        messages.filter { $0.role != .system }
    }

    var pinnedVisibleMessages: [ChatMessage] {
        messages.filter { pinnedMessages.contains($0.id) }
    }

    var conversationTitle: String {
        conversation.title ?? messages.first(where: { $0.role == .user })?.content.prefixWords(6) ?? "New chat"
    }

    func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isGenerating else { return }

        let userMsg = ChatMessage.userMessage(trimmed)
        append(userMsg)
        refreshPulse()
        isGenerating = true
        streamingText = ""

        generationTask?.cancel()
        generationTask = Task { [selectedMode] in
            var response = ""
            let configuration = SwarmConfiguration.automatic(
                mode: selectedMode,
                prompt: trimmed,
                parameters: .default
            )

            for await event in orchestrator.runSwarm(configuration: configuration) {
                if Task.isCancelled { return }

                switch event {
                case .telemetry(let snapshot):
                    await MainActor.run {
                        self.swarmSnapshot = snapshot
                    }
                case .token(let token):
                    response += token
                    await MainActor.run {
                        self.streamingText = response
                    }
                case .halted(let reason, let snapshot):
                    await MainActor.run {
                        self.swarmSnapshot = snapshot
                        self.pulse.caution = reason
                    }
                case .completed(let text, let snapshot):
                    response = text
                    await MainActor.run {
                        self.swarmSnapshot = snapshot
                    }
                case .failed(let message, let snapshot):
                    await MainActor.run {
                        self.swarmSnapshot = snapshot
                        self.pulse.caution = message
                    }
                }
            }

            await MainActor.run {
                self.finishAssistantResponse(response)
            }
        }
    }

    func stopGeneration() {
        generationTask?.cancel()
        generationTask = nil
        if !streamingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            finishAssistantResponse(streamingText + "\n\nStopped.")
        } else {
            streamingText = ""
            isGenerating = false
        }
    }

    func regenerateLastAssistant() {
        guard !isGenerating else { return }
        if let lastAssistantIndex = messages.lastIndex(where: { $0.role == .assistant }) {
            messages.remove(at: lastAssistantIndex)
            syncConversationMessages()
        }
        guard let lastUser = messages.last(where: { $0.role == .user }) else { return }
        sendMessage(lastUser.content)
    }

    func clearConversation() {
        generationTask?.cancel()
        let welcome = ChatMessage.assistantMessage("Fresh workspace. Pick a mode or send the next task.")
        conversation = Conversation(systemPrompt: Self.defaultSystemPrompt)
        messages = [welcome]
        conversation.messages.append(welcome)
        pinnedMessages = []
        streamingText = ""
        isGenerating = false
        swarmSnapshot = .idle
        shadowInsights = []
        refreshPulse()
        refreshTokenBudget()
    }

    func togglePin(_ message: ChatMessage) {
        if pinnedMessages.contains(message.id) {
            pinnedMessages.remove(message.id)
        } else {
            pinnedMessages.insert(message.id)
        }
    }

    func setSystemPrompt(_ prompt: String) {
        if let index = conversation.messages.firstIndex(where: { $0.role == .system }) {
            conversation.messages[index] = ChatMessage.systemPrompt(prompt)
        } else {
            conversation.messages.insert(ChatMessage.systemPrompt(prompt), at: 0)
        }
    }

    func ragDocuments() async -> [ImportedDocument] {
        await VectorStore.shared.allDocuments()
    }

    @discardableResult
    func importDocument(at url: URL) async throws -> ImportedDocument {
        try await documentImporter.importDocument(at: url)
    }

    func removeRAGDocument(id: UUID) async {
        await VectorStore.shared.removeDocument(id: id)
    }

    func runShadowSynthesis() {
        Task {
            let insights = await shadowMemory.synthesize(
                conversation: conversation,
                mode: selectedMode,
                pinnedMessages: pinnedVisibleMessages
            )
            await MainActor.run {
                self.shadowInsights = insights
            }
        }
    }

    private func streamFallbackResponse(for prompt: String, mode: NeuralMode) async {
        let response = fallbackResponse(for: prompt, mode: mode)
        var partial = ""

        for character in response {
            if Task.isCancelled { return }
            partial.append(character)
            await MainActor.run {
                self.streamingText = partial
            }
            try? await Task.sleep(nanoseconds: 8_000_000)
        }

        await MainActor.run {
            self.finishAssistantResponse(response)
        }
    }

    private func fallbackResponse(for prompt: String, mode: NeuralMode) -> String {
        let lead: String
        switch mode {
        case .copilot:
            lead = "Here is the cleanest way to move this forward:"
        case .researcher:
            lead = "I would frame the research brief like this:"
        case .builder:
            lead = "I would ship this as a practical build path:"
        case .coach:
            lead = "Let us make the next step feel smaller and clearer:"
        }

        return """
        \(lead)

        1. Define the outcome: \(prompt.prefixWords(14)).
        2. Separate what is known from what needs a decision.
        3. Pick one next action that can be completed in under 30 minutes.

        Neural Pulse is tracking this as \(mode.behavior). Load a local model to replace this guided fallback with full generation.
        """
    }

    private func append(_ message: ChatMessage) {
        messages.append(message)
        conversation.messages.append(message)
        conversation.lastUpdatedAt = Date()
        if conversation.title == nil, message.role == .user {
            conversation.title = message.content.prefixWords(7)
        }
        refreshTokenBudget()
    }

    private func finishAssistantResponse(_ response: String) {
        let clean = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let assistant = ChatMessage.assistantMessage(clean.isEmpty ? "I do not have output yet. Load a model or try again." : clean)
        append(assistant)
        streamingText = ""
        isGenerating = false
        generationTask = nil
        refreshPulse()
        runShadowSynthesis()
    }

    private func syncConversationMessages() {
        let systemPrompt = conversation.systemPrompt ?? ChatMessage.systemPrompt(Self.defaultSystemPrompt)
        conversation.messages = [systemPrompt] + messages
        conversation.lastUpdatedAt = Date()
        refreshTokenBudget()
        refreshPulse()
    }

    private func refreshTokenBudget() {
        contextTokensUsed = messages.reduce(0) { total, message in
            total + (message.tokenInfo?.totalTokenCount ?? MessageTokenInfo.estimate(from: message.content, role: message.role).totalTokenCount)
        }
    }

    private func refreshPulse() {
        let lastUser = messages.last(where: { $0.role == .user })?.content ?? ""
        let userCount = messages.filter { $0.role == .user }.count
        let assistantCount = messages.filter { $0.role == .assistant }.count

        let intent = lastUser.isEmpty
            ? "Choose a direction"
            : lastUser.prefixWords(10)
        let momentum = userCount == 0
            ? "Ready"
            : "\(userCount) asks, \(assistantCount) responses"

        let nextMoves: [String]
        if lastUser.isEmpty {
            nextMoves = selectedMode.starterPrompts
        } else {
            nextMoves = [
                "Ask for a concise version",
                "Turn this into a checklist",
                "Pin the key answer for later"
            ]
        }

        let caution = contextTokensUsed > 1_500
            ? "Context is getting full. Consider pinning the important bits."
            : "Context budget is healthy."
        let lastArtifact = messages.compactMap(\.artifact).last
        let sandboxStatus = lastArtifact.map {
            "\($0.title), ~\(ByteCountFormatter.string(fromByteCount: Int64($0.estimatedMemoryBytes), countStyle: .memory))"
        } ?? "No artifact mounted"
        let insight = shadowInsights.first?.summary

        pulse = NeuralPulse(
            intent: intent,
            momentum: momentum,
            nextMoves: nextMoves,
            caution: caution,
            consensus: swarmSnapshot.state.rawValue,
            localTokenRate: swarmSnapshot.local.tokensPerSecond,
            remoteTokenRate: swarmSnapshot.remote?.tokensPerSecond,
            confidence: swarmSnapshot.consensusScore,
            sandboxStatus: sandboxStatus,
            shadowInsight: insight
        )
    }
}

struct ShadowInsight: Identifiable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var summary: String
    var relatedTerms: [String]
    var confidence: Double
    var createdAt = Date()
}

private actor ShadowMemorySynthesizer {
    func synthesize(
        conversation: Conversation,
        mode: NeuralMode,
        pinnedMessages: [ChatMessage]
    ) async -> [ShadowInsight] {
        let documents = await VectorStore.shared.allDocuments()
        let documentNames = documents.prefix(5).map(\.filename)
        let text = (conversation.conversationalMessages + pinnedMessages)
            .map(\.content)
            .joined(separator: " ")

        let terms = keyTerms(in: text)
        guard !terms.isEmpty || !documentNames.isEmpty else { return [] }

        let title: String
        switch mode {
        case .researcher:
            title = "Research thread emerging"
        case .builder:
            title = "Build plan memory"
        case .copilot:
            title = "Workspace continuity"
        case .coach:
            title = "Momentum cue"
        }

        let documentHint = documentNames.isEmpty
            ? "No imported documents are linked yet."
            : "Linked knowledge: \(documentNames.joined(separator: ", "))."

        return [
            ShadowInsight(
                title: title,
                summary: "Shadow Memory sees recurring focus around \(terms.prefix(4).joined(separator: ", ")). \(documentHint)",
                relatedTerms: Array(terms.prefix(8)),
                confidence: min(0.95, 0.45 + Double(terms.count) / 20.0)
            )
        ]
    }

    private func keyTerms(in text: String) -> [String] {
        let stopWords: Set<String> = [
            "this", "that", "with", "from", "have", "your", "about", "into",
            "what", "when", "where", "will", "would", "should", "there",
            "their", "make", "more", "need", "just", "like", "than"
        ]
        let words = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 && !stopWords.contains($0) }

        let counts = Dictionary(grouping: words, by: { $0 }).mapValues(\.count)
        return counts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .map(\.key)
    }
}

private actor LightweightDocumentImporter {
    func importDocument(at url: URL) async throws -> ImportedDocument {
        let ext = url.pathExtension.lowercased()
        guard ["txt", "md"].contains(ext) else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }

        let text = try String(contentsOf: url, encoding: .utf8)
        let documentId = UUID()
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? UInt64(text.utf8.count)
        let chunks = chunk(text: text, documentId: documentId, filename: url.lastPathComponent)
        let totalTokens = chunks.reduce(0) { $0 + $1.estimatedTokens }
        let document = ImportedDocument(
            id: documentId,
            filename: url.lastPathComponent,
            fileType: ext,
            fileSize: fileSize,
            importDate: Date(),
            chunkCount: chunks.count,
            totalEstimatedTokens: totalTokens
        )
        await VectorStore.shared.addChunks(chunks, document: document)
        return document
    }

    private func chunk(text: String, documentId: UUID, filename: String) -> [DocumentChunk] {
        let paragraphs = text
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let groups = stride(from: 0, to: paragraphs.count, by: 4).map { start in
            paragraphs[start..<min(start + 4, paragraphs.count)].joined(separator: "\n")
        }

        return groups.enumerated().map { index, body in
            DocumentChunk(
                id: UUID(),
                documentId: documentId,
                documentName: filename,
                text: body,
                chunkIndex: index,
                embedding: LightweightDocumentImporter.embedding(for: body),
                rangeStart: 0,
                estimatedTokens: max(1, Int(Double(body.count) / 3.8))
            )
        }
    }

    private static func embedding(for text: String) -> [Float] {
        var vector = [Float](repeating: 0, count: 32)
        for scalar in text.lowercased().unicodeScalars {
            let index = Int(scalar.value) % vector.count
            vector[index] += 1
        }
        let magnitude = sqrt(vector.reduce(Float(0)) { $0 + ($1 * $1) })
        guard magnitude > 0 else { return vector }
        return vector.map { $0 / magnitude }
    }
}

private extension String {
    func prefixWords(_ limit: Int) -> String {
        let words = split(separator: " ")
        guard words.count > limit else { return self }
        return words.prefix(limit).joined(separator: " ") + "..."
    }
}
