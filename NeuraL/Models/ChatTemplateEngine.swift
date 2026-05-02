//
//  ChatTemplateEngine.swift
//  NeuraL
//
//  Phase 2 — Chat Templating Engine
//
//  This module converts a Conversation (array of ChatMessage structs) into
//  a single formatted string that the model can understand. Different model
//  families use different chat formats; this engine supports:
//
//  1. Llama-3 format (used by Llama-3.1, Llama-3.2, Qwen2.5)
//  2. Gemma format (used by Gemma-2, Phi-2/3)
//  3. ChatML format (used by some fine-tuned models)
//  4. Raw passthrough (no formatting, for debugging)
//
//  Why not use llama.cpp's built-in chat template?
//  - llama.cpp does have llama_chat_apply_template(), but it requires the
//    model to have a chat_template in its GGUF metadata. Many quantized
//    models are missing this field, and the C API for it is clunky from Swift.
//  - Our implementation gives us full control over formatting, making it
//    easy to test, debug, and extend with custom templates.
//  - We can compute exact token estimates per-message for context management.
//
//  CRITICAL: The formatted string must end with the assistant header
//  (e.g., "<|start_header_id|>assistant<|end_header_id|>\n\n") so the
//  model continues generating as the assistant.
//

import Foundation

// MARK: - Template Format

/// Supported chat template formats.
///
/// When selecting a format, match it to the model you're using:
/// - Llama-3.x models → .llama3
/// - Gemma-2, Phi-2/3 → .gemma
/// - Mistral/Mixtral with ChatML → .chatML
/// - If unsure, check the model's GGUF metadata for "tokenizer.chat_template"
enum ChatTemplateFormat: String, Sendable, Codable, CaseIterable, CustomStringConvertible {
    case llama3
    case gemma
    case chatML
    case raw

    var description: String {
        switch self {
        case .llama3: return "Llama-3 / Llama-3.1 / Llama-3.2 / Qwen2.5"
        case .gemma:  return "Gemma-2 / Phi-2 / Phi-3"
        case .chatML: return "ChatML (Mistral fine-tunes)"
        case .raw:    return "Raw (no formatting)"
        }
    }

    /// Auto-detect the template format from a model's architecture name.
    ///
    /// This is a best-effort heuristic. If the model has a chat_template
    /// in its GGUF metadata, that should take precedence.
    static func detect(from architecture: String) -> ChatTemplateFormat {
        let lower = architecture.lowercased()
        if lower.contains("llama") || lower.contains("qwen2") {
            return .llama3
        } else if lower.contains("gemma") || lower.contains("phi") {
            return .gemma
        } else if lower.contains("mistral") || lower.contains("mixtral") {
            return .chatML
        } else {
            // Default to Llama-3 as it's the most common format
            return .llama3
        }
    }
}

// MARK: - Template Engine

/// Formats a Conversation into a prompt string suitable for the model.
///
/// Usage:
/// ```swift
/// let engine = ChatTemplateEngine(format: .llama3)
/// let prompt = engine.formatPrompt(
///     conversation: conversation,
///     forGeneration: true
/// )
/// ```
struct ChatTemplateEngine: Sendable {

    let format: ChatTemplateFormat

    // MARK: - Assistant Header

    /// The assistant header string for the current template format.
    /// This is the text that signals "the assistant should now speak" and is
    /// appended after the conversation history but before the model generates.
    ///
    /// Used by ChatState to tokenize and process just the header after
    /// context eviction, so the model knows to start generating as the assistant.
    var assistantHeaderForFormat: String {
        switch format {
        case .llama3:
            return "<|start_header_id|>assistant<|end_header_id|>\n\n"
        case .gemma:
            return "<start_of_turn>model\n"
        case .chatML:
            return "<|im_start|>assistant\n"
        case .raw:
            return ""
        }
    }

    // MARK: - Format Prompt

    /// Format a conversation into a single prompt string.
    ///
    /// - Parameters:
    ///   - conversation: The conversation to format.
    ///   - forGeneration: If true, the prompt ends with the assistant header
    ///     so the model continues generating. If false, the prompt is formatted
    ///     for display or token counting without the trailing assistant header.
    /// - Returns: The formatted prompt string.
    func formatPrompt(
        conversation: Conversation,
        forGeneration: Bool = true
    ) -> String {
        switch format {
        case .llama3:
            return formatLlama3(conversation: conversation, forGeneration: forGeneration)
        case .gemma:
            return formatGemma(conversation: conversation, forGeneration: forGeneration)
        case .chatML:
            return formatChatML(conversation: conversation, forGeneration: forGeneration)
        case .raw:
            return formatRaw(conversation: conversation, forGeneration: forGeneration)
        }
    }

    /// Format only a subset of messages (used after context eviction
    /// when we need to re-format the remaining conversation).
    func formatPrompt(
        messages: [ChatMessage],
        forGeneration: Bool = true
    ) -> String {
        let tempConversation = Conversation(messages: messages)
        return formatPrompt(conversation: tempConversation, forGeneration: forGeneration)
    }

    // MARK: - Llama-3 Format

    /// Llama-3 / Llama-3.1 / Llama-3.2 / Qwen2.5 chat format.
    ///
    /// Format:
    /// ```
    /// <|begin_of_text|><|start_header_id|>system<|end_header_id|>
    ///
    /// {system_message}<|eot_id|><|start_header_id|>user<|end_header_id|>
    ///
    /// {user_message}<|eot_id|><|start_header_id|>assistant<|end_header_id|>
    ///
    /// {assistant_message}<|eot_id|><|start_header_id|>assistant<|end_header_id|>
    ///
    /// ```
    ///
    /// The final assistant header (without EOT) signals the model to generate.
    private func formatLlama3(
        conversation: Conversation,
        forGeneration: Bool
    ) -> String {
        var parts: [String] = ["<|begin_of_text|>"]

        for (index, message) in conversation.messages.enumerated() {
            switch message.role {
            case .system:
                parts.append("<|start_header_id|>system<|end_header_id|>\n\n\(message.content)<|eot_id|>")
            case .user:
                parts.append("<|start_header_id|>user<|end_header_id|>\n\n\(message.content)<|eot_id|>")
            case .assistant:
                if forGeneration && index == conversation.messages.count - 1 {
                    // The last assistant message is the one being generated.
                    // We don't include its content; we just start the header.
                    parts.append("<|start_header_id|>assistant<|end_header_id|>\n\n")
                } else {
                    parts.append("<|start_header_id|>assistant<|end_header_id|>\n\n\(message.content)<|eot_id|>")
                }
            }
        }

        // If the last message is from the user, add the assistant header
        // so the model knows to generate a response.
        if forGeneration, conversation.messages.last?.role == .user {
            parts.append("<|start_header_id|>assistant<|end_header_id|>\n\n")
        }

        return parts.joined()
    }

    // MARK: - Gemma Format

    /// Gemma-2 / Phi-2 / Phi-3 chat format.
    ///
    /// Format:
    /// ```
    /// <start_of_turn>user
    /// {user_message}<end_of_turn>
    /// <start_of_turn>model
    /// {assistant_message}<end_of_turn>
    /// <start_of_turn>model
    /// ```
    ///
    /// Note: Gemma uses "model" instead of "assistant" for the role name.
    /// System prompts are prepended to the first user message.
    private func formatGemma(
        conversation: Conversation,
        forGeneration: Bool
    ) -> String {
        var parts: [String] = []

        // Gemma doesn't have a native system role. We prepend the system
        // prompt to the first user message.
        var isFirstUserMessage = true
        let systemContent = conversation.systemPrompt?.content

        for (index, message) in conversation.messages.enumerated() {
            switch message.role {
            case .system:
                // Skip; will be prepended to first user message
                break

            case .user:
                let content: String
                if isFirstUserMessage, let systemContent = systemContent {
                    content = "\(systemContent)\n\n\(message.content)"
                    isFirstUserMessage = false
                } else {
                    content = message.content
                }
                parts.append("<start_of_turn>user\n\(content)<end_of_turn>\n")

            case .assistant:
                if forGeneration && index == conversation.messages.count - 1 {
                    parts.append("<start_of_turn>model\n")
                } else {
                    parts.append("<start_of_turn>model\n\(message.content)<end_of_turn>\n")
                }
            }
        }

        // Add model header for generation
        if forGeneration, conversation.messages.last?.role == .user {
            parts.append("<start_of_turn>model\n")
        }

        return parts.joined()
    }

    // MARK: - ChatML Format

    /// ChatML format (used by Mistral fine-tunes and some other models).
    ///
    /// Format:
    /// ```
    /// <|im_start|>system
    /// {system_message}<|im_end|>
    /// <|im_start|>user
    /// {user_message}<|im_end|>
    /// <|im_start|>assistant
    /// {assistant_message}<|im_end|>
    /// <|im_start|>assistant
    /// ```
    private func formatChatML(
        conversation: Conversation,
        forGeneration: Bool
    ) -> String {
        var parts: [String] = []

        for (index, message) in conversation.messages.enumerated() {
            switch message.role {
            case .system:
                parts.append("<|im_start|>system\n\(message.content)<|im_end|>\n")
            case .user:
                parts.append("<|im_start|>user\n\(message.content)<|im_end|>\n")
            case .assistant:
                if forGeneration && index == conversation.messages.count - 1 {
                    parts.append("<|im_start|>assistant\n")
                } else {
                    parts.append("<|im_start|>assistant\n\(message.content)<|im_end|>\n")
                }
            }
        }

        // Add assistant header for generation
        if forGeneration, conversation.messages.last?.role == .user {
            parts.append("<|im_start|>assistant\n")
        }

        return parts.joined()
    }

    // MARK: - Raw Format

    /// No formatting — just concatenate message contents with newlines.
    /// Useful for debugging or for models that don't use chat templates.
    private func formatRaw(
        conversation: Conversation,
        forGeneration: Bool
    ) -> String {
        conversation.messages.map(\.content).joined(separator: "\n\n")
    }

    // MARK: - Token Estimation

    /// Estimate the number of tokens a formatted prompt will produce.
    ///
    /// This is a rough estimate based on character count. For precise
    /// counting, the LlamaCppBridge's tokenize() method should be used.
    /// However, this estimate is useful for pre-generation planning
    /// (deciding whether to evict context before sending the prompt).
    ///
    /// - Parameters:
    ///   - conversation: The conversation to estimate.
    ///   - forGeneration: Whether to include the trailing assistant header.
    /// - Returns: Estimated token count.
    func estimateTokenCount(
        conversation: Conversation,
        forGeneration: Bool = true
    ) -> Int {
        let prompt = formatPrompt(conversation: conversation, forGeneration: forGeneration)
        // Average ~3.8 chars/token for English text with template overhead
        return max(1, Int(Double(prompt.utf8.count) / 3.5))
    }

    /// Estimate the token count for a single message within a template.
    func estimateTokenCount(for message: ChatMessage) -> Int {
        let roleOverhead: Int
        switch format {
        case .llama3: roleOverhead = 12  // <|start_header_id|>...<|end_header_id|>\n\n<|eot_id|>
        case .gemma:  roleOverhead = 8   // <start_of_turn>...\n<end_of_turn>\n
        case .chatML: roleOverhead = 10  // <|im_start|>...\n<|im_end|>\n
        case .raw:    roleOverhead = 2   // \n\n
        }
        let contentTokens = max(1, Int(Double(message.content.utf8.count) / 3.8))
        return contentTokens + roleOverhead
    }
}
