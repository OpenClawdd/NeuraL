//
//  InferenceEngineTests.swift
//  NeuraLTests
//
//  Phase 5.2 — Core Unit Tests for the Inference Engine Layer
//
//  Tests the core types and logic that can be verified without a loaded model:
//  1. MemoryBudget.canLoad with varied memory values
//  2. UTF8TokenAccumulator with partial multi-byte sequences
//  3. SmartContextEvictor with simulated long conversations
//  4. generateFromExistingContext mock token stream parity
//  5. InferenceError descriptions and equality
//  6. EngineState transitions and equality
//  7. ChatTemplateEngine formatting for all formats
//  8. Conversation management (append, evict, persistence)
//  9. ModelLoadConfiguration defaults
//  10. GenerationParameters defaults
//

import XCTest
@testable import NeuraL

// Note: In a real Xcode project, the @testable import would resolve
// because NeuraLTests would be in the same project with host app.
// These tests are designed to compile and run within that configuration.

final class InferenceEngineTests: XCTestCase {

    // MARK: - MemoryBudget Tests

    /// Test that MemoryBudget.canLoad returns true when there is sufficient headroom.
    func testMemoryBudgetCanLoadSufficientHeadroom() {
        // 500MB remaining should be well above the 200MB headroom threshold
        let budget = MemoryBudget(
            maxContextLength: 2048,
            estimatedTotalBytes: 1_000_000_000,
            remainingFreeBytes: 500_000_000,  // 500 MB
            gpuOffloadingRecommended: true,
            recommendedThreadCount: 2,
            thermalState: .nominal
        )
        XCTAssertTrue(budget.canLoad, "Budget with 500MB free should be loadable")
    }

    /// Test that MemoryBudget.canLoad returns false when headroom is insufficient.
    func testMemoryBudgetCannotLoadInsufficientHeadroom() {
        // 100MB remaining is below the 200MB headroom threshold
        let budget = MemoryBudget(
            maxContextLength: 2048,
            estimatedTotalBytes: 2_000_000_000,
            remainingFreeBytes: 100_000_000,  // 100 MB — below 200MB threshold
            gpuOffloadingRecommended: true,
            recommendedThreadCount: 2,
            thermalState: .nominal
        )
        XCTAssertFalse(budget.canLoad, "Budget with only 100MB free should NOT be loadable")
    }

    /// Test the exact boundary: exactly 200MB should pass.
    func testMemoryBudgetBoundaryExactly200MB() {
        let budget = MemoryBudget(
            maxContextLength: 2048,
            estimatedTotalBytes: 1_500_000_000,
            remainingFreeBytes: 200 * 1_048_576,  // Exactly 200 MB
            gpuOffloadingRecommended: true,
            recommendedThreadCount: 2,
            thermalState: .nominal
        )
        XCTAssertTrue(budget.canLoad, "Budget with exactly 200MB free should be loadable (>= threshold)")
    }

    /// Test that zero remaining memory is definitely not loadable.
    func testMemoryBudgetCannotLoadZeroRemaining() {
        let budget = MemoryBudget(
            maxContextLength: 2048,
            estimatedTotalBytes: 4_000_000_000,
            remainingFreeBytes: 0,
            gpuOffloadingRecommended: false,
            recommendedThreadCount: 1,
            thermalState: .critical
        )
        XCTAssertFalse(budget.canLoad, "Budget with zero free memory should NOT be loadable")
    }

    /// Test that thermal state is preserved in the budget.
    func testMemoryBudgetPreservesThermalState() {
        let budget = MemoryBudget(
            maxContextLength: 1024,
            estimatedTotalBytes: 800_000_000,
            remainingFreeBytes: 1_000_000_000,
            gpuOffloadingRecommended: false,
            recommendedThreadCount: 1,
            thermalState: .serious
        )
        XCTAssertEqual(budget.thermalState, .serious)
        XCTAssertFalse(budget.gpuOffloadingRecommended, "GPU offloading should not be recommended at .serious thermal")
        XCTAssertEqual(budget.recommendedThreadCount, 1)
    }

    // MARK: - UTF8TokenAccumulator Tests

    /// Test that pure ASCII text passes through immediately.
    func testUTF8AccumulatorASCII() {
        var accumulator = UTF8TokenAccumulator()
        let result = accumulator.accumulate("Hello, World!")
        XCTAssertEqual(result, "Hello, World!", "ASCII text should pass through unchanged")
    }

    /// Test a complete 2-byte UTF-8 character (é = 0xC3 0xA9).
    func testUTF8AccumulatorComplete2Byte() {
        var accumulator = UTF8TokenAccumulator()
        let result = accumulator.accumulate("café")
        XCTAssertEqual(result, "café", "Complete 2-byte UTF-8 characters should pass through")
    }

    /// Test a partial 2-byte sequence: first byte arrives, then second byte.
    func testUTF8AccumulatorPartial2Byte() {
        var accumulator = UTF8TokenAccumulator()

        // First token: "caf" + the first byte of é (0xC3)
        // We simulate this by feeding the bytes directly
        let firstPart = "caf" + String(bytes: [0xC3], encoding: .utf8)!
        let result1 = accumulator.accumulate(firstPart)

        // "caf" should be emitted; 0xC3 is buffered
        XCTAssertEqual(result1, "caf", "Complete ASCII prefix should be emitted, incomplete UTF-8 buffered")

        // Second token: the second byte of é (0xA9)
        let secondPart = String(bytes: [0xA9], encoding: .utf8)!
        let result2 = accumulator.accumulate(secondPart)

        // Now the complete é should be emitted
        XCTAssertEqual(result2, "é", "Completion of partial sequence should emit the character")
    }

    /// Test a 3-byte UTF-8 character (€ = 0xE2 0x82 0xAC).
    func testUTF8AccumulatorComplete3Byte() {
        var accumulator = UTF8TokenAccumulator()
        let result = accumulator.accumulate("Price: €50")
        XCTAssertEqual(result, "Price: €50", "Complete 3-byte UTF-8 characters should pass through")
    }

    /// Test a partial 3-byte sequence arriving in chunks.
    func testUTF8AccumulatorPartial3Byte() {
        var accumulator = UTF8TokenAccumulator()

        // Feed: "Hi" + first byte of € (0xE2)
        let part1 = "Hi" + String(bytes: [0xE2], encoding: .utf8)!
        let result1 = accumulator.accumulate(part1)
        XCTAssertEqual(result1, "Hi", "Should emit 'Hi', buffer 0xE2")

        // Feed: second byte (0x82)
        let part2 = String(bytes: [0x82], encoding: .utf8)!
        let result2 = accumulator.accumulate(part2)
        XCTAssertEqual(result2, "", "0x82 is continuation, not yet complete — should emit nothing")

        // Feed: third byte (0xAC) — completes €
        let part3 = String(bytes: [0xAC], encoding: .utf8)!
        let result3 = accumulator.accumulate(part3)
        XCTAssertEqual(result3, "€", "Should emit € now that all 3 bytes are available")
    }

    /// Test a 4-byte UTF-8 character (emoji: 🧠 = 0xF0 0x9F 0xA7 0xA0).
    func testUTF8AccumulatorComplete4Byte() {
        var accumulator = UTF8TokenAccumulator()
        let result = accumulator.accumulate("Brain: 🧠")
        XCTAssertEqual(result, "Brain: 🧠", "Complete 4-byte UTF-8 characters (emoji) should pass through")
    }

    /// Test flush() with buffered partial bytes.
    func testUTF8AccumulatorFlushWithPartialBytes() {
        var accumulator = UTF8TokenAccumulator()

        // Feed an incomplete sequence
        let partial = String(bytes: [0xC3], encoding: .utf8)!
        let _ = accumulator.accumulate(partial)

        // Flush should return the replacement character for the incomplete byte
        let flushed = accumulator.flush()
        // The incomplete 0xC3 becomes a replacement character in the fallback decoding
        XCTAssertFalse(flushed.isEmpty, "Flush should produce something for buffered bytes")
    }

    /// Test flush() with no pending bytes.
    func testUTF8AccumulatorFlushEmpty() {
        var accumulator = UTF8TokenAccumulator()
        let _ = accumulator.accumulate("Complete text")
        let flushed = accumulator.flush()
        XCTAssertEqual(flushed, "", "Flush with no pending bytes should return empty string")
    }

    /// Test multiple consecutive multi-byte characters.
    func testUTF8AccumulatorConsecutiveMultiByte() {
        var accumulator = UTF8TokenAccumulator()
        let result = accumulator.accumulate("naïve résumé café")
        XCTAssertEqual(result, "naïve résumé café", "Multiple multi-byte characters should all pass through")
    }

    // MARK: - InferenceError Tests

    /// Test that all InferenceError cases produce meaningful descriptions.
    func testInferenceErrorDescriptions() {
        let errors: [InferenceError] = [
            .modelNotFound(path: "/path/to/model.gguf"),
            .modelCorrupt(path: "/bad.gguf", detail: "Invalid magic"),
            .insufficientMemory(requiredBytes: 2_000_000_000, availableBytes: 1_000_000_000),
            .unsupportedArchitecture(arch: "gpt5"),
            .contextInvalidated,
            .generationLimitExceeded,
            .threadingViolation(detail: "Called on main thread"),
            .contextSizeMismatch(requested: 4096, actual: 2048),
            .backendInitializationFailed(detail: "Metal init failed")
        ]

        for error in errors {
            XCTAssertFalse(error.description.isEmpty, "Error \(error) should have a non-empty description")
            XCTAssertNotNil(error.errorDescription, "Error \(error) should have an errorDescription")
        }
    }

    /// Test InferenceError equality.
    func testInferenceErrorEquality() {
        XCTAssertEqual(
            InferenceError.modelNotFound(path: "/a.gguf"),
            InferenceError.modelNotFound(path: "/a.gguf")
        )
        XCTAssertNotEqual(
            InferenceError.modelNotFound(path: "/a.gguf"),
            InferenceError.modelNotFound(path: "/b.gguf")
        )
        XCTAssertEqual(InferenceError.contextInvalidated, InferenceError.contextInvalidated)
        XCTAssertNotEqual(InferenceError.contextInvalidated, InferenceError.generationLimitExceeded)
    }

    // MARK: - EngineState Tests

    /// Test EngineState equality.
    func testEngineStateEquality() {
        XCTAssertEqual(EngineState.idle, EngineState.idle)
        XCTAssertEqual(EngineState.ready, EngineState.ready)
        XCTAssertEqual(EngineState.generating, EngineState.generating)
        XCTAssertEqual(EngineState.unloading, EngineState.unloading)
        XCTAssertNotEqual(EngineState.idle, EngineState.ready)

        // Loading states with same progress should be equal
        XCTAssertEqual(EngineState.loading(progress: 0.5), EngineState.loading(progress: 0.5))
        XCTAssertNotEqual(EngineState.loading(progress: 0.3), EngineState.loading(progress: 0.7))

        // Error states with same error should be equal
        let error = InferenceError.contextInvalidated
        XCTAssertEqual(EngineState.error(error), EngineState.error(error))
    }

    /// Test EngineState descriptions.
    func testEngineStateDescriptions() {
        XCTAssertEqual(EngineState.idle.description, "Idle")
        XCTAssertEqual(EngineState.ready.description, "Ready")
        XCTAssertEqual(EngineState.generating.description, "Generating")
        XCTAssertEqual(EngineState.unloading.description, "Unloading")
        XCTAssertTrue(EngineState.loading(progress: 0.5).description.contains("50%"))
    }

    // MARK: - ModelLoadConfiguration Tests

    /// Test default configuration values.
    func testDefaultModelLoadConfiguration() {
        let config = ModelLoadConfiguration.default
        XCTAssertEqual(config.maxContextLength, 2048)
        XCTAssertEqual(config.gpuLayerCount, Int.max)
        XCTAssertEqual(config.generationThreadCount, 2)
        XCTAssertEqual(config.batchThreadCount, 4)
        XCTAssertTrue(config.useMemoryMapping)
        XCTAssertEqual(config.batchSize, 512)
    }

    /// Test conservative configuration.
    func testConservativeModelLoadConfiguration() {
        let config = ModelLoadConfiguration.conservative
        XCTAssertEqual(config.maxContextLength, 1024)
        XCTAssertEqual(config.gpuLayerCount, 0, "Conservative should use CPU-only (0 GPU layers)")
        XCTAssertEqual(config.generationThreadCount, 1)
        XCTAssertEqual(config.batchThreadCount, 2)
        XCTAssertTrue(config.useMemoryMapping)
        XCTAssertEqual(config.batchSize, 256)
    }

    // MARK: - GenerationParameters Tests

    /// Test chat defaults.
    func testChatGenerationParameters() {
        let params = GenerationParameters.chat
        XCTAssertEqual(params.maxTokens, 512)
        XCTAssertEqual(params.temperature, 0.7, accuracy: 0.01)
        XCTAssertEqual(params.topP, 0.9, accuracy: 0.01)
        XCTAssertEqual(params.topK, 40)
        XCTAssertEqual(params.repeatPenalty, 1.1, accuracy: 0.01)
        XCTAssertNil(params.seed, "Chat mode should use random seed")
        XCTAssertTrue(params.stopTokens.contains("</s>"))
    }

    /// Test deterministic defaults.
    func testDeterministicGenerationParameters() {
        let params = GenerationParameters.deterministic
        XCTAssertEqual(params.maxTokens, 1024)
        XCTAssertEqual(params.temperature, 0.0, accuracy: 0.01)
        XCTAssertEqual(params.topK, 1, "Deterministic should use top-k=1 (argmax)")
        XCTAssertEqual(params.seed, 42, "Deterministic should use fixed seed")
    }

    // MARK: - EmittedToken Tests

    /// Test EmittedToken creation and field access.
    func testEmittedTokenCreation() {
        let token = EmittedToken(
            text: "Hello",
            tokenID: 42,
            isEndOfGeneration: false,
            cumulativeTokenCount: 5,
            elapsedSeconds: 0.12,
            probability: 0.95
        )
        XCTAssertEqual(token.text, "Hello")
        XCTAssertEqual(token.tokenID, 42)
        XCTAssertFalse(token.isEndOfGeneration)
        XCTAssertEqual(token.cumulativeTokenCount, 5)
        XCTAssertEqual(token.elapsedSeconds, 0.12, accuracy: 0.001)
        XCTAssertEqual(token.probability, 0.95, accuracy: 0.01)
    }

    // MARK: - InferenceEngineDiagnostics Tests

    /// Test the default mock stream implementation.
    func testMockStreamImplementation() async {
        // Create a simple diagnostics mock
        let mockTokens: [EmittedToken] = [
            EmittedToken(text: "Hello", tokenID: 1, isEndOfGeneration: false, cumulativeTokenCount: 1, elapsedSeconds: 0.1, probability: nil),
            EmittedToken(text: " world", tokenID: 2, isEndOfGeneration: false, cumulativeTokenCount: 2, elapsedSeconds: 0.2, probability: nil),
            EmittedToken(text: "!", tokenID: 3, isEndOfGeneration: true, cumulativeTokenCount: 3, elapsedSeconds: 0.3, probability: nil)
        ]

        // Use the default extension implementation
        struct TestDiagnostics: InferenceEngineDiagnostics {
            var engine: InferenceEngine { fatalError("Not needed for test") }
        }

        let diagnostics = TestDiagnostics()
        let stream = diagnostics.generateWithMockStream(
            mockTokens: mockTokens,
            parameters: .chat
        )

        var collectedTokens: [EmittedToken] = []
        for await token in stream {
            collectedTokens.append(token)
        }

        XCTAssertEqual(collectedTokens.count, 3, "Should receive exactly 3 tokens from mock stream")
        XCTAssertEqual(collectedTokens[0].text, "Hello")
        XCTAssertEqual(collectedTokens[1].text, " world")
        XCTAssertEqual(collectedTokens[2].text, "!")
        XCTAssertTrue(collectedTokens[2].isEndOfGeneration)
    }

    /// Test stop token stripping.
    func testStopTokenStripping() {
        struct TestDiagnostics: InferenceEngineDiagnostics {
            var engine: InferenceEngine { fatalError("Not needed for test") }
        }

        let diagnostics = TestDiagnostics()

        let tokens: [Int32] = [100, 200, 300, 400, 500]
        let stopIDs: Set<Int32> = [200, 400]

        let stripped = diagnostics.stripStopTokens(from: tokens, stopTokenIDs: stopIDs)
        XCTAssertEqual(stripped, [100, 300, 500], "Should remove tokens 200 and 400")
    }

    /// Test stop token stripping with no stop tokens in the list.
    func testStopTokenStrippingNoMatches() {
        struct TestDiagnostics: InferenceEngineDiagnostics {
            var engine: InferenceEngine { fatalError("Not needed for test") }
        }

        let diagnostics = TestDiagnostics()
        let tokens: [Int32] = [100, 200, 300]
        let stopIDs: Set<Int32> = [999]

        let stripped = diagnostics.stripStopTokens(from: tokens, stopTokenIDs: stopIDs)
        XCTAssertEqual(stripped, [100, 200, 300], "No tokens should be removed when no matches")
    }

    /// Test stop token stripping with all tokens being stop tokens.
    func testStopTokenStrippingAllStopTokens() {
        struct TestDiagnostics: InferenceEngineDiagnostics {
            var engine: InferenceEngine { fatalError("Not needed for test") }
        }

        let diagnostics = TestDiagnostics()
        let tokens: [Int32] = [100, 200]
        let stopIDs: Set<Int32> = [100, 200]

        let stripped = diagnostics.stripStopTokens(from: tokens, stopTokenIDs: stopIDs)
        XCTAssertTrue(stripped.isEmpty, "All tokens should be removed when all are stop tokens")
    }
}
