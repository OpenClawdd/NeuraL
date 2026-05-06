import Foundation

struct DreamSynthesizer {
    func synthesize(
        latestUserPrompt: String,
        assistantAnswer: String,
        reasoningTrace: String?,
        selectedNeuralMode: String,
        pinnedMessages: [String],
        importedDocumentNames: [String],
        sourceMessageID: UUID
    ) -> DreamCard {
        let lines = assistantAnswer.split(separator: "\n").map(String.init)
        let nextAction = lines.first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("-") || $0.trimmingCharacters(in: .whitespaces).first?.isNumber == true }?
            .replacingOccurrences(of: "^-|^\\d+[\\.)]\\s*", with: "", options: .regularExpression) ?? "Refine this idea into the next local step."

        let title = String(assistantAnswer.prefix(60)).trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = String(assistantAnswer.prefix(220)).trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = extractTags(from: [latestUserPrompt, assistantAnswer, selectedNeuralMode] + pinnedMessages + importedDocumentNames)
        let confidence = confidenceScore(prompt: latestUserPrompt, answer: assistantAnswer, trace: reasoningTrace)

        return DreamCard(
            title: title.isEmpty ? "Dream formed" : title,
            summary: summary,
            nextAction: nextAction,
            rememberedTheme: importedDocumentNames.first,
            sourceMessageID: sourceMessageID,
            confidence: confidence,
            tags: tags
        )
    }

    private func extractTags(from sources: [String]) -> [String] {
        let stopWords: Set<String> = ["the","and","for","that","with","from","this","into","your","have","will"]
        let words = sources.joined(separator: " ").lowercased().split { !$0.isLetter }
        let counts = Dictionary(words.filter { $0.count > 3 && !stopWords.contains(String($0)) }.map { (String($0), 1) }, uniquingKeysWith: +)
        return counts.sorted { $0.value > $1.value }.prefix(5).map { $0.key }
    }

    private func confidenceScore(prompt: String, answer: String, trace: String?) -> Double {
        let hasTrace = (trace?.isEmpty == false) ? 0.2 : 0.0
        let lengthScore = min(Double(answer.count) / 500.0, 0.5)
        let overlap = Set(prompt.lowercased().split(separator: " ")).intersection(Set(answer.lowercased().split(separator: " "))).count
        let overlapScore = min(Double(overlap) / 20.0, 0.3)
        return min(1.0, 0.2 + hasTrace + lengthScore + overlapScore)
    }
}
