//
//  SmartContextEvictor.swift
//  NeuraL
//
//  Phase 2 â€” Intelligent Context Window Eviction with System Prompt Preservation
//
//  The SmartContextEvictor solves the central problem of on-device LLM inference:
//  the context window is finite, but conversations grow indefinitely.
//
//  Naive approach (Phase 1): Evict tokens from position 0.
//    âŒ This destroys the system prompt, causing the model to lose its
//      behavioral constraints and produce off-topic or harmful output.
//    âŒ It also destroys the beginning of the conversation, removing
//      important context that later messages reference.
//
//  Smart approach (Phase 2): Message-boundary-aware eviction.
//    âœ… ALWAYS preserves the system prompt.
//    âœ… Evicts complete (user, assistant) turn pairs â€” never partial messages.
//    âœ… Evicts from the oldest turn first (FIFO).
//    âœ… After eviction, re-formats the remaining conversation and re-processes
//      the prompt to rebuild the KV cache from scratch.
//    âœ… Reserves tokens for the upcoming generation (configurable headroom).
//
//  Why re-process instead of shifting the KV cache?
//    - llama_kv_cache_seq_shift() only adjusts position indices; it doesn't
//      recalculate attention patterns. With RoPE positional encodings, shifted
//      positions may produce subtly wrong attention scores.
//    - Re-processing is slower (~0.5-2s for a typical conversation) but
//      guarantees mathematically correct KV cache state.
//    - On-device, correctness > speed for context management operations.
//

import Foundation
import os

// MARK: - Eviction Result

/// The result of a context eviction operation.
struct EvictionResult: @unchecked Sendable {
    /// Number of messages evicted.
    let messagesEvicted: Int

    /// Number of tokens freed by the eviction.
    let tokensFreed: Int

    /// Number of turns (user+assistant pairs) evicted.
    let turnsEvicted: Int

    /// Whether the system prompt was preserved.
    let systemPromptPreserved: Bool

    /// The remaining conversation after eviction.
    let remainingConversation: Conversation

    /// The formatted prompt for re-processing (after eviction).
    let reformattedPrompt: String

    var description: String {
        "Evicted \(turnsEvicted) turns (\(messagesEvicted) messages, \(tokensFreed) tokens). System prompt preserved: \(systemPromptPreserved)"
    }
}

// MARK: - Eviction Strategy

/// Strategy for how aggressively to evict context.
enum EvictionStrategy: Sendable {
    /// Evict the minimum number of turns to fit within the budget.
    /// This preserves the most conversation context but may require
    /// frequent re-evictions as the conversation grows.
    case conservative

    /// Evict enough turns to leave 25% of the context window free,
    /// reducing the frequency of re-evictions at the cost of losing
    /// more conversation history.
    case balanced

    /// Evict enough turns to leave 50% of the context window free.
    /// Best for long conversations where you expect many more turns.
    case aggressive

    /// The fraction of the context window to keep free after eviction.
    var freeSpaceTarget: Double {
        switch self {
        case .conservative: return 0.10  // Keep 10% free
        case .balanced:     return 0.25  // Keep 25% free
        case .aggressive:   return 0.50  // Keep 50% free
        }
    }
}

// MARK: - Smart Context Evictor

/// Manages context window eviction with system prompt preservation.
///
/// This actor coordinates with the MemoryManager and InferenceOrchestrator
/// to ensure that the conversation fits within the device's memory budget
/// while always preserving the system prompt.
///
/// Lifecycle:
/// 1. Before each generation, check if the conversation + estimated reply
///    will exceed the context window.
/// 2. If so, compute an eviction plan that removes the oldest turns.
/// 3. Re-format the remaining conversation.
/// 4. Clear the KV cache and re-process the reformatted prompt.
///
/// Usage:
/// ```swift
/// let evictor = SmartContextEvictor(templateEngine: templateEngine)
/// let result = await evictor.evictIfNeeded(
///     conversation: conversation,
///     maxContextTokens: 2048,
///     reservedForGeneration: 512,
///     strategy: .balanced
/// )
/// if let result = result {
///     // Need to re-process: clear KV cache and process the reformatted prompt
///     await bridge.clearKVCache()
///     let tokens = await bridge.tokenize(text: result.reformattedPrompt, addBOS: false, special: true)
///     try await bridge.processPrompt(tokens: tokens)
/// }
/// ```
actor SmartContextEvictor {

    private let templateEngine: ChatTemplateEngine
    private let logger = Logger(subsystem: "com.neural.engine", category: "ContextEvictor")

    init(templateEngine: ChatTemplateEngine) {
        self.templateEngine = templateEngine
    }

    // MARK: - Eviction Check

    /// Check whether eviction is needed for the given conversation.
    ///
    /// - Parameters:
    ///   - conversation: The current conversation.
    ///   - maxContextTokens: Maximum tokens the context window can hold.
    ///   - reservedForGeneration: Tokens to reserve for the upcoming reply.
    /// - Returns: True if eviction is needed.
    func needsEviction(
        conversation: Conversation,
        maxContextTokens: Int,
        reservedForGeneration: Int
    ) -> Bool {
        let estimatedTokens = templateEngine.estimateTokenCount(
            conversation: conversation,
            forGeneration: true
        )
        let effectiveBudget = maxContextTokens - reservedForGeneration
        return estimatedTokens > effectiveBudget
    }

    // MARK: - Eviction Execution

    /// Perform context eviction if needed, returning the result with the
    /// reformatted prompt for re-processing.
    ///
    /// - Parameters:
    ///   - conversation: The current conversation.
    ///   - maxContextTokens: Maximum tokens the context window can hold.
    ///   - reservedForGeneration: Tokens to reserve for the upcoming reply.
    ///   - strategy: How aggressively to evict.
    /// - Returns: An EvictionResult if eviction was performed, or nil if
    ///           the conversation fits within the budget.
    func evictIfNeeded(
        conversation: Conversation,
        maxContextTokens: Int,
        reservedForGeneration: Int = 512,
        strategy: EvictionStrategy = .balanced
    ) -> EvictionResult? {
        let estimatedTokens = templateEngine.estimateTokenCount(
            conversation: conversation,
            forGeneration: true
        )
        let effectiveBudget = maxContextTokens - reservedForGeneration

        guard estimatedTokens > effectiveBudget else {
            logger.debug("No eviction needed. Estimated \(estimatedTokens) tokens, budget \(effectiveBudget).")
            return nil
        }

//         logger.info("Eviction needed. Estimated \(estimatedTokens) tokens, budget \(effectiveBudget). Applying \(strategy) strategy.")

        return performEviction(
            conversation: conversation,
            maxContextTokens: maxContextTokens,
            reservedForGeneration: reservedForGeneration,
            strategy: strategy
        )
    }

    /// Force eviction even if the conversation technically fits.
    /// Useful for preemptive eviction before a long expected reply.
    func forceEvict(
        conversation: Conversation,
        maxContextTokens: Int,
        reservedForGeneration: Int = 512,
        strategy: EvictionStrategy = .balanced
    ) -> EvictionResult {
        performEviction(
            conversation: conversation,
            maxContextTokens: maxContextTokens,
            reservedForGeneration: reservedForGeneration,
            strategy: strategy
        )
    }

    // MARK: - Private Implementation

    private func performEviction(
        conversation: Conversation,
        maxContextTokens: Int,
        reservedForGeneration: Int,
        strategy: EvictionStrategy
    ) -> EvictionResult {
        var workingConversation = conversation
        var turnsEvicted = 0
        var messagesEvicted = 0
        var tokensFreed = 0

        // Calculate the target token count based on strategy
        let targetFreeTokens = Int(Double(maxContextTokens) * strategy.freeSpaceTarget)
        let targetBudget = maxContextTokens - targetFreeTokens - reservedForGeneration

        // Iteratively evict the oldest turns until we fit within the target
        while true {
            let currentEstimate = templateEngine.estimateTokenCount(
                conversation: workingConversation,
                forGeneration: true
            )

            if currentEstimate <= targetBudget {
                break
            }

            // Check if there are any evictable turns left
            let hasEvictableTurns = workingConversation.conversationalMessages
                .contains(where: { $0.role == .user })

            if !hasEvictableTurns {
                logger.warning("No more evictable turns. Conversation still exceeds budget after removing all user/assistant pairs.")
                break
            }

            // Evict the oldest turn
            let freed = workingConversation.evictOldestTurn()
            turnsEvicted += 1
            tokensFreed += freed

            // Count messages evicted (user + potentially assistant)
            messagesEvicted += freed > 0 ? 2 : 1  // Approximation
        }

        // Verify the system prompt was preserved
        let systemPreserved = workingConversation.systemPrompt != nil &&
                              workingConversation.systemPrompt?.role == .system

        // Re-format the remaining conversation
        let reformattedPrompt = templateEngine.formatPrompt(
            conversation: workingConversation,
            forGeneration: true
        )

        logger.info("Eviction complete: \(turnsEvicted) turns, \(messagesEvicted) messages, \(tokensFreed) tokens freed. System prompt preserved: \(systemPreserved)")

        return EvictionResult(
            messagesEvicted: messagesEvicted,
            tokensFreed: tokensFreed,
            turnsEvicted: turnsEvicted,
            systemPromptPreserved: systemPreserved,
            remainingConversation: workingConversation,
            reformattedPrompt: reformattedPrompt
        )
    }

    // MARK: - Context Budget Analysis

    /// Analyze the current context utilization for display in the UI.
    struct ContextAnalysis: Sendable {
        /// Total tokens estimated in the formatted prompt.
        let estimatedTokens: Int
        /// Maximum context window size.
        let maxContextTokens: Int
        /// Tokens reserved for generation.
        let reservedForGeneration: Int
        /// Available tokens for conversation.
        let availableForConversation: Int
        /// Percentage of context used.
        let utilizationPercent: Double
        /// Number of turns that can be added before eviction is needed.
        let turnsBeforeEviction: Int

        var isNearLimit: Bool {
            utilizationPercent > 0.85
        }

        var description: String {
            String(format: "Context: %d/%d tokens (%.0f%% used, %d turns until eviction)",
                   estimatedTokens, maxContextTokens, utilizationPercent * 100, turnsBeforeEviction)
        }
    }

    /// Analyze the current context utilization.
    func analyzeContext(
        conversation: Conversation,
        maxContextTokens: Int,
        reservedForGeneration: Int = 512
    ) -> ContextAnalysis {
        let estimated = templateEngine.estimateTokenCount(
            conversation: conversation,
            forGeneration: true
        )
        let available = maxContextTokens - reservedForGeneration
        let utilization = available > 0 ? Double(estimated) / Double(available) : 1.0
        let remaining = available - estimated

        // Estimate turns before eviction: assume ~200 tokens per turn average
        let turnsBeforeEviction = max(0, remaining / 200)

        return ContextAnalysis(
            estimatedTokens: estimated,
            maxContextTokens: maxContextTokens,
            reservedForGeneration: reservedForGeneration,
            availableForConversation: available,
            utilizationPercent: min(1.0, utilization),
            turnsBeforeEviction: turnsBeforeEviction
        )
    }
}

