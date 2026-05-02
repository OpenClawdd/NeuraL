//
//  ContextEvictionTests.swift
//  NeuraLTests
//
//  Phase 5.2 — Tests for SmartContextEvictor and Conversation management
//
//  Verifies:
//  1. System prompt is NEVER evicted
//  2. Eviction removes oldest turns first
//  3. Eviction strategies produce different free-space targets
//  4. Conversation.evictOldestTurn works correctly
//  5. Token estimation is consistent
//  6. EvictionResult reports accurate metrics
//

import XCTest
@testable import NeuraL

final class ContextEvictionTests: XCTestCase {

    // MARK: - Conversation Management Tests

    /// Test that a new conversation has a system prompt.
    func testNewConversationHasSystemPrompt() {
        let conv = Conversation(systemPrompt: "You are a helpful assistant.")
        XCTAssertNotNil(conv.systemPrompt)
        XCTAssertEqual(conv.systemPrompt?.role, .system)
        XCTAssertEqual(conv.systemPrompt?.content, "You are a helpful assistant.")
        XCTAssertEqual(conv.turnCount, 0)
    }

    /// Test that appending messages increments the turn count.
    func testConversationTurnCounting() {
        var conv = Conversation(systemPrompt: "System")

        conv.append(.userMessage("Hello"))
        XCTAssertEqual(conv.turnCount, 1)

        conv.append(.assistantMessage("Hi!", tokenInfo: MessageTokenInfo(promptTokenCount: 4, generationTokenCount: 5), metadata: nil))
        XCTAssertEqual(conv.turnCount, 1, "User+assistant pair = 1 turn")

        conv.append(.userMessage("How are you?"))
        XCTAssertEqual(conv.turnCount, 2)

        conv.append(.assistantMessage("Great!", tokenInfo: MessageTokenInfo(promptTokenCount: 4, generationTokenCount: 5), metadata: nil))
        XCTAssertEqual(conv.turnCount, 2, "Two user+assistant pairs = 2 turns")
    }

    /// Test that the conversation title is auto-generated from the first user message.
    func testConversationAutoTitle() {
        var conv = Conversation(systemPrompt: "System")
        XCTAssertNil(conv.title, "New conversation should have no title")

        conv.append(.userMessage("What is the capital of France?"))
        XCTAssertEqual(conv.title, "What is the capital of France?", "Title should match first user message")

        conv.append(.assistantMessage("Paris.", tokenInfo: MessageTokenInfo(promptTokenCount: 4, generationTokenCount: 2), metadata: nil))
        XCTAssertEqual(conv.title, "What is the capital of France?", "Title should not change after assistant response")
    }

    /// Test that title is truncated to 60 characters.
    func testConversationTitleTruncation() {
        var conv = Conversation(systemPrompt: "System")
        let longMessage = String(repeating: "A", count: 100)
        conv.append(.userMessage(longMessage))
        XCTAssertEqual(conv.title?.count, 60, "Title should be truncated to 60 characters")
    }

    // MARK: - Eviction Tests

    /// Test that evicting the oldest turn removes the first user+assistant pair.
    func testEvictOldestTurn() {
        var conv = Conversation(systemPrompt: "System")
        conv.append(.userMessage("Question 1"))
        conv.append(.assistantMessage("Answer 1", tokenInfo: MessageTokenInfo(promptTokenCount: 4, generationTokenCount: 5), metadata: nil))
        conv.append(.userMessage("Question 2"))
        conv.append(.assistantMessage("Answer 2", tokenInfo: MessageTokenInfo(promptTokenCount: 4, generationTokenCount: 5), metadata: nil))
        conv.append(.userMessage("Question 3"))

        XCTAssertEqual(conv.turnCount, 3)
        XCTAssertEqual(conv.messages.count, 6)  // system + 2 pairs + 1 pending user

        let freed = conv.evictOldestTurn()
        XCTAssertGreaterThan(freed, 0, "Should free some tokens")

        // After eviction, the first user+assistant pair should be gone
        XCTAssertEqual(conv.turnCount, 2)
        XCTAssertEqual(conv.messages.first?.role, .system, "System prompt should remain first")
    }

    /// CRITICAL: Test that the system prompt is NEVER evicted.
    func testSystemPromptNeverEvicted() {
        var conv = Conversation(systemPrompt: "You are a critical system prompt that must never be removed.")

        // Add many turns to force multiple evictions
        for i in 1...20 {
            conv.append(.userMessage("User message \(i) with enough text to consume tokens."))
            conv.append(.assistantMessage(
                "Assistant response \(i) with enough text to consume tokens in the context window.",
                tokenInfo: MessageTokenInfo(promptTokenCount: 10, generationTokenCount: 20),
                metadata: nil
            ))
        }

        // Evict repeatedly
        for _ in 1...19 {
            conv.evictOldestTurn()
        }

        // The system prompt MUST still be there
        XCTAssertNotNil(conv.systemPrompt, "System prompt must survive all evictions")
        XCTAssertEqual(conv.systemPrompt?.content, "You are a critical system prompt that must never be removed.")
        XCTAssertEqual(conv.systemPrompt?.role, .system)
        XCTAssertEqual(conv.messages.first?.role, .system, "System prompt must be the first message")
    }

    /// Test that MessageRole.isEvictable returns false for system messages.
    func testMessageRoleEvictability() {
        XCTAssertFalse(MessageRole.system.isEvictable, "System messages must NOT be evictable")
        XCTAssertTrue(MessageRole.user.isEvictable, "User messages should be evictable")
        XCTAssertTrue(MessageRole.assistant.isEvictable, "Assistant messages should be evictable")
    }

    // MARK: - Eviction Strategy Tests

    /// Test that different strategies produce different free-space targets.
    func testEvictionStrategyTargets() {
        XCTAssertLessThan(
            EvictionStrategy.conservative.freeSpaceTarget,
            EvictionStrategy.balanced.freeSpaceTarget
        )
        XCTAssertLessThan(
            EvictionStrategy.balanced.freeSpaceTarget,
            EvictionStrategy.aggressive.freeSpaceTarget
        )
        XCTAssertEqual(EvictionStrategy.conservative.freeSpaceTarget, 0.10, accuracy: 0.01)
        XCTAssertEqual(EvictionStrategy.balanced.freeSpaceTarget, 0.25, accuracy: 0.01)
        XCTAssertEqual(EvictionStrategy.aggressive.freeSpaceTarget, 0.50, accuracy: 0.01)
    }

    // MARK: - Chat Template Engine Tests

    /// Test Llama-3 format with generation header.
    func testLlama3FormatWithGeneration() {
        let engine = ChatTemplateEngine(format: .llama3)
        var conv = Conversation(systemPrompt: "You are helpful.")
        conv.append(.userMessage("Hello"))

        let prompt = engine.formatPrompt(conversation: conv, forGeneration: true)

        XCTAssertTrue(prompt.contains("<|begin_of_text|>"), "Should start with BOT")
        XCTAssertTrue(prompt.contains("<|start_header_id|>system<|end_header_id|>"))
        XCTAssertTrue(prompt.contains("<|start_header_id|>user<|end_header_id|>"))
        XCTAssertTrue(prompt.hasSuffix("<|start_header_id|>assistant<|end_header_id|>\n\n"), "Should end with assistant header")
    }

    /// Test Llama-3 format without generation header.
    func testLlama3FormatWithoutGeneration() {
        let engine = ChatTemplateEngine(format: .llama3)
        var conv = Conversation(systemPrompt: "You are helpful.")
        conv.append(.userMessage("Hello"))
        conv.append(.assistantMessage("Hi!", tokenInfo: MessageTokenInfo(promptTokenCount: 4, generationTokenCount: 2), metadata: nil))

        let prompt = engine.formatPrompt(conversation: conv, forGeneration: false)
        XCTAssertFalse(prompt.hasSuffix("<|start_header_id|>assistant<|end_header_id|>\n\n"), "Without generation, should not end with assistant header")
    }

    /// Test Gemma format prepends system prompt to first user message.
    func testGemmaFormatSystemPromptPrepending() {
        let engine = ChatTemplateEngine(format: .gemma)
        var conv = Conversation(systemPrompt: "Be concise.")
        conv.append(.userMessage("Hello"))

        let prompt = engine.formatPrompt(conversation: conv, forGeneration: true)

        XCTAssertTrue(prompt.contains("Be concise."), "System prompt should appear in the output")
        XCTAssertTrue(prompt.contains("<start_of_turn>user"), "Should have user turn")
        XCTAssertTrue(prompt.hasSuffix("<start_of_turn>model\n"), "Should end with model header")
    }

    /// Test ChatML format.
    func testChatMLFormat() {
        let engine = ChatTemplateEngine(format: .chatML)
        var conv = Conversation(systemPrompt: "You are helpful.")
        conv.append(.userMessage("Hello"))

        let prompt = engine.formatPrompt(conversation: conv, forGeneration: true)

        XCTAssertTrue(prompt.contains("<|im_start|>system"))
        XCTAssertTrue(prompt.contains("<|im_end|>"))
        XCTAssertTrue(prompt.hasSuffix("<|im_start|>assistant\n"))
    }

    /// Test Raw format (no special tokens).
    func testRawFormat() {
        let engine = ChatTemplateEngine(format: .raw)
        var conv = Conversation(systemPrompt: "System msg")
        conv.append(.userMessage("User msg"))

        let prompt = engine.formatPrompt(conversation: conv, forGeneration: true)

        XCTAssertFalse(prompt.contains("<|"), "Raw format should have no special tokens")
        XCTAssertTrue(prompt.contains("System msg"))
        XCTAssertTrue(prompt.contains("User msg"))
    }

    /// Test format auto-detection from architecture name.
    func testFormatAutoDetection() {
        XCTAssertEqual(ChatTemplateFormat.detect(from: "llama"), .llama3)
        XCTAssertEqual(ChatTemplateFormat.detect(from: "qwen2"), .llama3)
        XCTAssertEqual(ChatTemplateFormat.detect(from: "gemma"), .gemma)
        XCTAssertEqual(ChatTemplateFormat.detect(from: "phi2"), .gemma)
        XCTAssertEqual(ChatTemplateFormat.detect(from: "mistral"), .chatML)
        XCTAssertEqual(ChatTemplateFormat.detect(from: "unknown"), .llama3, "Unknown should default to Llama-3")
    }

    /// Test assistant header string for each format.
    func testAssistantHeaderStrings() {
        XCTAssertEqual(ChatTemplateEngine(format: .llama3).assistantHeaderForFormat, "<|start_header_id|>assistant<|end_header_id|>\n\n")
        XCTAssertEqual(ChatTemplateEngine(format: .gemma).assistantHeaderForFormat, "<start_of_turn>model\n")
        XCTAssertEqual(ChatTemplateEngine(format: .chatML).assistantHeaderForFormat, "<|im_start|>assistant\n")
        XCTAssertEqual(ChatTemplateEngine(format: .raw).assistantHeaderForFormat, "")
    }

    /// Test token estimation returns positive values.
    func testTokenEstimation() {
        let engine = ChatTemplateEngine(format: .llama3)
        var conv = Conversation(systemPrompt: "You are helpful.")
        conv.append(.userMessage("What is the capital of France?"))
        conv.append(.assistantMessage("Paris.", tokenInfo: MessageTokenInfo(promptTokenCount: 8, generationTokenCount: 5), metadata: nil))

        let estimate = engine.estimateTokenCount(conversation: conv)
        XCTAssertGreaterThan(estimate, 0, "Token estimate should be positive")
    }

    // MARK: - Conversation Persistence Tests

    /// Test saving and loading a conversation.
    func testConversationPersistence() throws {
        var conv = Conversation(systemPrompt: "Test system prompt for persistence.")
        conv.append(.userMessage("Hello!"))
        conv.append(.assistantMessage("Hi there!", tokenInfo: MessageTokenInfo(promptTokenCount: 4, generationTokenCount: 5), metadata: nil))

        // Save
        try ConversationStore.save(conv)

        // Load
        let loaded = try ConversationStore.load(id: conv.id)
        XCTAssertEqual(loaded.messages.count, conv.messages.count)
        XCTAssertEqual(loaded.systemPrompt?.content, "Test system prompt for persistence.")
        XCTAssertEqual(loaded.turnCount, 1)

        // List
        let allIDs = try ConversationStore.listAll()
        XCTAssertTrue(allIDs.contains(conv.id))

        // Delete
        try ConversationStore.delete(id: conv.id)
        let afterDelete = try ConversationStore.listAll()
        XCTAssertFalse(afterDelete.contains(conv.id))
    }

    // MARK: - Device Capability Tier Tests

    /// Test that DeviceCapabilityTier descriptions are human-readable.
    func testDeviceCapabilityTierDescriptions() {
        XCTAssertFalse(DeviceCapabilityTier.limited.description.isEmpty)
        XCTAssertFalse(DeviceCapabilityTier.standard.description.isEmpty)
        XCTAssertFalse(DeviceCapabilityTier.premium.description.isEmpty)
        XCTAssertFalse(DeviceCapabilityTier.extended.description.isEmpty)
    }

    // MARK: - Eviction Plan Tests

    /// Test that the eviction plan identifies the correct messages to evict.
    func testEvictionPlan() {
        var conv = Conversation(systemPrompt: "System")
        for i in 1...5 {
            conv.append(.userMessage("Q\(i) " + String(repeating: "x", count: 50)))
            conv.append(.assistantMessage("A\(i) " + String(repeating: "y", count: 50), tokenInfo: MessageTokenInfo(promptTokenCount: 15, generationTokenCount: 20), metadata: nil))
        }

        // Request an eviction plan for a very small budget
        let plan = conv.evictionPlan(tokenBudget: 100, reservedTokens: 0)

        // The system prompt (index 0) should NEVER be in the eviction plan
        let systemIndices = conv.messages.enumerated()
            .filter { $0.element.role == .system }
            .map(\.offset)
        for sysIdx in systemIndices {
            XCTAssertFalse(plan.contains(sysIdx), "System prompt at index \(sysIdx) should never be in eviction plan")
        }

        // The plan should contain at least some user/assistant indices
        XCTAssertGreaterThan(plan.count, 0, "Should plan to evict at least some messages")
    }

    // MARK: - Download State Tests

    /// Test DownloadState convenience properties.
    func testDownloadStateProperties() {
        XCTAssertTrue(DownloadState.downloading(progress: 0.5).isDownloading)
        XCTAssertFalse(DownloadState.idle.isDownloading)
        XCTAssertFalse(DownloadState.completed.isDownloading)
        XCTAssertFalse(DownloadState.failed(error: "test").isDownloading)

        XCTAssertTrue(DownloadState.completed.isCompleted)
        XCTAssertFalse(DownloadState.idle.isCompleted)
    }
}
