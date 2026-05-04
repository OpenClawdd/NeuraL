import Foundation

struct ParsedGeneration: Equatable, Sendable {
    var reasoningTrace: String?
    var answer: String
    var isInsideThought: Bool
    var didCloseThought: Bool
    var traceWasTruncated: Bool
    var traceTokenEstimate: Int

    var hasTrace: Bool {
        guard let reasoningTrace else { return false }
        return !reasoningTrace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum ThinkTagParser {
    private static let openTag = "<think>"
    private static let closeTag = "</think>"
    private static let maxStoredTraceCharacters = 12_000

    static func parse(_ rawText: String) -> ParsedGeneration {
        guard let openRange = rawText.range(of: openTag, options: [.caseInsensitive]) else {
            let cleaned = stripLooseThinkClosers(from: rawText)
            return ParsedGeneration(
                reasoningTrace: nil,
                answer: cleaned.trimmingCharacters(in: .whitespacesAndNewlines),
                isInsideThought: false,
                didCloseThought: false,
                traceWasTruncated: false,
                traceTokenEstimate: 0
            )
        }

        let prefix = String(rawText[..<openRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let afterOpen = openRange.upperBound

        guard let closeRange = rawText[afterOpen...].range(of: closeTag, options: [.caseInsensitive]) else {
            let rawTrace = String(rawText[afterOpen...])
            let storedTrace = truncateTrace(rawTrace)
            return ParsedGeneration(
                reasoningTrace: storedTrace.text,
                answer: prefix,
                isInsideThought: true,
                didCloseThought: false,
                traceWasTruncated: storedTrace.wasTruncated,
                traceTokenEstimate: estimateTokens(storedTrace.text)
            )
        }

        let rawTrace = String(rawText[afterOpen..<closeRange.lowerBound])
        let storedTrace = truncateTrace(rawTrace)
        let suffix = String(rawText[closeRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let answer = [prefix, suffix]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ParsedGeneration(
            reasoningTrace: storedTrace.text,
            answer: answer,
            isInsideThought: false,
            didCloseThought: true,
            traceWasTruncated: storedTrace.wasTruncated,
            traceTokenEstimate: estimateTokens(storedTrace.text)
        )
    }

    static func traceSummary(for trace: String?) -> String? {
        guard let trace = trace?.trimmingCharacters(in: .whitespacesAndNewlines), !trace.isEmpty else {
            return nil
        }

        let sentences = trace
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: ".")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let first = sentences.first {
            return String(first.prefix(180)) + (first.count > 180 ? "…" : ".")
        }

        return String(trace.prefix(180)) + (trace.count > 180 ? "…" : "")
    }

    private static func truncateTrace(_ text: String) -> (text: String, wasTruncated: Bool) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > maxStoredTraceCharacters else {
            return (clean, false)
        }
        return (String(clean.prefix(maxStoredTraceCharacters)), true)
    }

    private static func estimateTokens(_ text: String) -> Int {
        max(1, Int(Double(text.count) / 3.8))
    }

    private static func stripLooseThinkClosers(from text: String) -> String {
        text.replacingOccurrences(of: closeTag, with: "", options: [.caseInsensitive])
    }
}
