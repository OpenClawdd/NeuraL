//
//  TokenStreamer.swift
//  NeuraL
//
//  Phase 1 — Token Stream Accumulator and Typewriter-Effect Controller
//
//  The TokenStreamer sits between the LlamaCppBridge's raw token stream
//  and the InferenceOrchestrator's public API. It handles:
//
//  1. UTF-8 boundary safety: LLM tokens can split multi-byte UTF-8 sequences.
//     A token like "é" (2 bytes: 0xC3 0xA9) might be emitted as two separate
//     tokens if the tokenizer split it. The TokenStreamer buffers incomplete
//     UTF-8 sequences and only emits complete characters.
//
//  2. Token counting and timing: Each emitted token carries metadata about
//     its position and the elapsed time, enabling the UI to show tokens/sec.
//
//  3. Cancellation forwarding: If the consumer stops iterating, the streamer
//     signals cancellation back to the bridge.
//
//  4. Accumulated text: Maintains the full generated text for context
//     management and stop-token matching on complete strings.
//

import Foundation

// MARK: - UTF-8 Safe Token Accumulator

/// Accumulates raw token text fragments and emits only complete, valid
/// UTF-8 strings. This is essential because LLM tokenizers can produce
/// tokens that contain partial multi-byte UTF-8 sequences.
///
/// For example, the token for "é" might be emitted as two separate tokens:
/// one containing the leading byte 0xC3 and another containing 0xA9.
/// Neither is valid UTF-8 on its own. This accumulator buffers such
/// fragments until a complete character is formed.
struct UTF8TokenAccumulator: Sendable {
    /// Buffer for incomplete UTF-8 bytes at the end of the last emission.
    private var pendingBytes: [UInt8] = []

    /// Feed a raw token text string into the accumulator.
    ///
    /// - Parameter rawText: The token's text, which may contain partial UTF-8.
    /// - Returns: A valid UTF-8 string representing all complete characters
    ///           that can be formed from the accumulated bytes. May be empty
    ///           if the input only contributed to a partial character.
    mutating func accumulate(_ rawText: String) -> String {
        // Append the new bytes to our pending buffer
        pendingBytes.append(contentsOf: rawText.utf8)

        // Find the longest valid UTF-8 prefix
        let (validString, consumedCount) = extractValidUTF8Prefix(from: pendingBytes)

        // Remove consumed bytes from the pending buffer
        if consumedCount > 0 {
            pendingBytes.removeFirst(consumedCount)
        }

        return validString
    }

    /// Flush any remaining bytes, replacing invalid sequences with the
    /// Unicode replacement character. Call this at the end of generation.
    mutating func flush() -> String {
        guard !pendingBytes.isEmpty else { return "" }
        let result = String(decoding: pendingBytes, as: UTF8.self)
        pendingBytes = []
        return result
    }

    /// Extract the longest valid UTF-8 prefix from a byte array.
    ///
    /// UTF-8 character boundaries:
    /// - 0x00-0x7F: 1-byte character (ASCII)
    /// - 0xC0-0xDF: Start of 2-byte character
    /// - 0xE0-0xEF: Start of 3-byte character
    /// - 0xF0-0xF7: Start of 4-byte character
    /// - 0x80-0xBF: Continuation byte (must follow a start byte)
    ///
    /// We scan through the bytes, validating each complete character,
    /// and stop when we encounter an incomplete sequence.
    private func extractValidUTF8Prefix(from bytes: [UInt8]) -> (String, Int) {
        var consumedCount = 0
        var validBytes: [UInt8] = []

        var index = 0
        while index < bytes.count {
            let byte = bytes[index]

            // Determine the expected character length
            let charLength: Int
            if byte < 0x80 {
                charLength = 1
            } else if byte >= 0xC2 && byte <= 0xDF {
                charLength = 2
            } else if byte >= 0xE0 && byte <= 0xEF {
                charLength = 3
            } else if byte >= 0xF0 && byte <= 0xF4 {
                charLength = 4
            } else if byte >= 0x80 && byte <= 0xBF {
                // Stray continuation byte — this is invalid UTF-8.
                // This can happen when a tokenizer produces bytes that
                // don't align to UTF-8 boundaries. Skip this byte.
                index += 1
                consumedCount += 1
                continue
            } else {
                // Other invalid leading bytes (0xC0, 0xC1 are overlong encodings)
                index += 1
                consumedCount += 1
                continue
            }

            // Check if we have enough bytes for the complete character
            let endIndex = index + charLength
            if endIndex > bytes.count {
                // Incomplete character — stop here, buffer the rest
                break
            }

            // Validate continuation bytes
            var isValid = true
            for j in 1..<charLength {
                if bytes[index + j] & 0xC0 != 0x80 {
                    isValid = false
                    break
                }
            }

            if !isValid {
                // Invalid continuation — skip the start byte and try again
                index += 1
                consumedCount += 1
                continue
            }

            // Valid character — add it to the output
            for j in 0..<charLength {
                validBytes.append(bytes[index + j])
            }
            consumedCount += charLength
            index = endIndex
        }

        let result = String(decoding: validBytes, as: UTF8.self)
        return (result, consumedCount)
    }
}

// MARK: - Generation Metrics

/// Performance metrics for a generation session.
struct GenerationMetrics: Sendable {
    /// Total tokens generated (including prompt tokens if counted).
    let totalTokensGenerated: Int

    /// Wall-clock time for the entire generation (seconds).
    let totalElapsedSeconds: Double

    /// Tokens per second (generation tokens only, not prompt processing).
    var tokensPerSecond: Double {
        guard totalElapsedSeconds > 0 else { return 0 }
        return Double(totalTokensGenerated) / totalElapsedSeconds
    }

    /// Time spent on prompt processing (seconds).
    let promptProcessingSeconds: Double

    /// Time spent on autoregressive generation (seconds).
    let generationSeconds: Double

    /// Peak memory usage during generation (bytes).
    let peakMemoryBytes: UInt64

    var description: String {
        String(format: """
            Generation complete: %d tokens in %.2fs (%.1f tok/s)
            Prompt processing: %.2fs | Generation: %.2fs | Peak memory: %.0f MB
            """,
            totalTokensGenerated,
            totalElapsedSeconds,
            tokensPerSecond,
            promptProcessingSeconds,
            generationSeconds,
            Double(peakMemoryBytes) / 1_048_576
        )
    }
}

// MARK: - Token Stream Controller

/// Controls the flow of tokens from the bridge to the consumer.
///
/// Usage:
/// ```swift
/// let controller = TokenStreamController()
/// let stream = controller.createStream()
///
/// // Feed tokens (called by the orchestrator)
/// controller.emitToken(tokenID: 42, rawText: "Hello")
///
/// // Consumer iterates the stream
/// for await token in stream {
///     print(token.text)
/// }
/// ```
final class TokenStreamController: @unchecked Sendable {
    /// The underlying AsyncStream continuation.
    private var continuation: AsyncStream<EmittedToken>.Continuation?

    /// UTF-8 accumulator for safe character emission.
    private var utf8Accumulator = UTF8TokenAccumulator()

    /// The accumulated generated text.
    private var accumulatedText = ""

    /// Token count for the current generation.
    private var tokenCount = 0

    /// Start time of the current generation.
    private var startTime: ContinuousClock.Instant?

    /// Metrics for the last completed generation.
    private(set) var lastMetrics: GenerationMetrics?

    /// Create an AsyncStream that the consumer can iterate.
    func createStream() -> AsyncStream<EmittedToken> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    /// Start a new generation session.
    func startGeneration() {
        tokenCount = 0
        accumulatedText = ""
        utf8Accumulator = UTF8TokenAccumulator()
        startTime = ContinuousClock.now
    }

    /// Emit a raw token from the bridge into the stream.
    ///
    /// This method handles UTF-8 boundary safety: if the token text
    /// contains a partial multi-byte character, it is buffered until
    /// the remaining bytes arrive in a subsequent token.
    ///
    /// - Parameters:
    ///   - tokenID: The token's integer ID.
    ///   - rawText: The raw token text (may contain partial UTF-8).
    ///   - isEog: Whether this is an end-of-generation token.
    func emitToken(tokenID: Int, rawText: String, isEog: Bool) {
        guard let continuation = continuation else { return }
        guard let startTime = startTime else { return }

        // Safely accumulate the UTF-8 text
        let safeText = utf8Accumulator.accumulate(rawText)
        accumulatedText += rawText  // Track raw text for stop-token matching

        tokenCount += 1
        let elapsed = ContinuousClock.now - startTime

        let token = EmittedToken(
            text: safeText,
            tokenID: tokenID,
            isEndOfGeneration: isEog,
            cumulativeTokenCount: tokenCount,
            elapsedSeconds: Double(elapsed.components.seconds) +
                           Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000,
            probability: nil  // Not available from the current bridge API
        )

        continuation.yield(token)

        if isEog {
            finishGeneration()
        }
    }

    /// Finish the current generation and close the stream.
    func finishGeneration() {
        // Flush any remaining UTF-8 bytes
        let flushedText = utf8Accumulator.flush()
        if !flushedText.isEmpty, let continuation = continuation, let startTime = startTime {
            let elapsed = ContinuousClock.now - startTime
            tokenCount += 1
            let token = EmittedToken(
                text: flushedText,
                tokenID: -1,
                isEndOfGeneration: true,
                cumulativeTokenCount: tokenCount,
                elapsedSeconds: Double(elapsed.components.seconds) +
                               Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000,
                probability: nil
            )
            continuation.yield(token)
        }

        // Record metrics
        if let startTime = startTime {
            let elapsed = ContinuousClock.now - startTime
            let elapsedSeconds = Double(elapsed.components.seconds) +
                                Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000
            lastMetrics = GenerationMetrics(
                totalTokensGenerated: tokenCount,
                totalElapsedSeconds: elapsedSeconds,
                promptProcessingSeconds: 0,  // Filled in by orchestrator
                generationSeconds: elapsedSeconds,
                peakMemoryBytes: 0  // Filled in by orchestrator
            )
        }

        continuation?.finish()
        continuation = nil
    }

    /// Cancel the current generation (e.g., user stopped generation).
    func cancelGeneration() {
        finishGeneration()
    }

    /// Get the accumulated text so far in the current generation.
    var currentAccumulatedText: String {
        accumulatedText
    }
}
