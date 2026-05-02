//
//  MarkdownRenderer.swift
//  NeuraL
//
//  Phase 3 — Safe Two-Phase Markdown Rendering
//  Phase 4 — Streaming Simplified Markdown (Mid-Stream Styling)
//
//  CRITICAL DESIGN DECISION: Two-phase rendering.
//
//  Phase A (streaming): Lightweight simplified markdown + cursor.
//    - During token generation, the streamingText may contain unclosed
//      markdown tags. Instead of showing raw delimiters like ** and _,
//      we apply a lightweight parser that:
//      * Strips and styles closed bold/italic pairs immediately
//      * Hides unclosed delimiters (they appear as plain text)
//      * Detects inline code with matched backticks
//      * Shows headers with larger font when a # line is complete
//    - A blinking cursor is appended to the end.
//
//  Phase B (finalized): Rich AttributedString with full markdown parsing.
//    - Once the full message is finalized (all tokens received), the
//      text is complete and markdown tags are properly closed.
//    - We parse with AttributedString(markdown:options:intent:) for
//      bold, italic, code, lists, links, and code blocks.
//    - If parsing fails (malformed markdown in model output), we fall
//      back to plain text rendering. Never crash on bad markdown.
//
//  Enhanced rendering strategy:
//    Apple's AttributedString(markdown:) with .inlineOnlyPreservingWhitespace
//    only handles inline elements (bold, italic, inline code, links).
//    It does NOT render code blocks (```...```), lists (- item), or
//    headers (# Title) as styled blocks.
//
//    Our approach: split the text into segments (code blocks vs. prose),
//    render each with the appropriate SwiftUI view, and compose the result.
//    Code blocks get a monospaced font + background. Prose sections get
//    full AttributedString markdown rendering.
//

import SwiftUI

// MARK: - Markdown Renderer

/// Renders markdown text safely for both streaming and finalized states.
///
/// Usage:
/// ```swift
/// // During streaming (simplified markdown + cursor):
/// MarkdownRenderer.streamText("Hello, **wor")
///
/// // After finalization (rich markdown):
/// MarkdownRenderer.renderedText("Hello, **world**!")
/// ```
enum MarkdownRenderer {

    // MARK: - Streaming Rendering (Simplified Markdown + Cursor)

    /// Render streaming text with lightweight markdown styling.
    ///
    /// This is safe for incomplete markdown because it only applies styles
    /// to completed delimiter pairs. Unclosed delimiters are hidden so the
    /// user never sees raw `**` or `_` symbols during generation.
    ///
    /// Handled inline elements (mid-stream safe):
    /// - Bold: **text** → bold text (delimiters hidden)
    /// - Italic: _text_ or *text* → italic text (delimiters hidden)
    /// - Inline code: `code` → monospaced text (delimiters hidden)
    /// - Headers: # / ## / ### at line start → larger font
    ///
    /// NOT handled during streaming (deferred to Phase B):
    /// - Fenced code blocks (```...```) — may be incomplete
    /// - Links [text](url) — may be incomplete
    /// - Lists (- item) — deferred to full parsing
    ///
    /// - Parameter text: The current streaming text (may be incomplete markdown).
    /// - Returns: A SwiftUI View showing styled text with a cursor.
    @ViewBuilder
    static func streamText(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            let lines = text.components(separatedBy: "\n")
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                if index == lines.count - 1 {
                    // Last line — might be incomplete, render with cursor
                    HStack(spacing: 0) {
                        renderStreamingLine(line)
                        CursorView()
                    }
                } else {
                    // Complete line
                    renderStreamingLine(line)
                }
            }
        }
    }

    /// Render a single line of streaming text with simplified markdown.
    @ViewBuilder
    private static func renderStreamingLine(_ line: String) -> some View {
        // Check for headers first
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        if trimmedLine.hasPrefix("### ") {
            Text(trimmedLine.dropFirst(4))
                .font(.headline)
                .foregroundStyle(.primary)
        } else if trimmedLine.hasPrefix("## ") {
            Text(trimmedLine.dropFirst(3))
                .font(.title3.bold())
                .foregroundStyle(.primary)
        } else if trimmedLine.hasPrefix("# ") {
            Text(trimmedLine.dropFirst(2))
                .font(.title2.bold())
                .foregroundStyle(.primary)
        } else {
            // Apply inline markdown styling
            renderInlineStreamingMarkdown(line)
        }
    }

    /// Render inline markdown for streaming text.
    ///
    /// Processes bold, italic, and inline code pairs. Unclosed delimiters
    /// are hidden (not shown as raw ** or _ characters). If the markdown
    /// structure is ambiguous, falls back to plain text.
    @ViewBuilder
    private static func renderInlineStreamingMarkdown(_ text: String) -> some View {
        let segments = parseStreamingInline(text)
        if segments.isEmpty {
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
        } else {
            HStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .plain(let content):
                        Text(content)
                            .font(.body)
                            .foregroundStyle(.primary)
                    case .bold(let content):
                        Text(content)
                            .font(.body.bold())
                            .foregroundStyle(.primary)
                    case .italic(let content):
                        Text(content)
                            .font(.body.italic())
                            .foregroundStyle(.primary)
                    case .code(let content):
                        Text(content)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
            }
        }
    }

    // MARK: - Streaming Inline Markdown Parser

    /// A segment of inline markdown during streaming.
    enum StreamingSegment {
        case plain(String)
        case bold(String)
        case italic(String)
        case code(String)
    }

    /// Parse inline markdown for streaming rendering.
    ///
    /// This is a lightweight parser that only processes completed delimiter
    /// pairs. It handles: **bold**, *italic*, _italic_, `code`.
    /// Unclosed delimiters are included as plain text (hidden from the user
    /// since they'll be closed in subsequent tokens).
    ///
    /// The parser works left-to-right, consuming the highest-priority
    /// delimiters first: inline code > bold > italic.
    static func parseStreamingInline(_ text: String) -> [StreamingSegment] {
        var segments: [StreamingSegment] = []
        var remaining = Substring(text)

        while !remaining.isEmpty {
            // Try inline code first (single backtick pair)
            if let codeRange = findMatchingPair(in: remaining, open: "`", close: "`") {
                // Text before the code
                if codeRange.lowerBound > remaining.startIndex {
                    let before = String(remaining[remaining.startIndex..<codeRange.lowerBound])
                    segments.append(contentsOf: parseBoldItalic(before))
                }
                // The code content (strip backticks)
                let codeContent = String(remaining[remaining.index(after: codeRange.lowerBound)..<codeRange.upperBound])
                segments.append(.code(codeContent))
                // Advance past the closing backtick
                remaining = remaining[remaining.index(after: codeRange.upperBound)...]
            }
            // Try bold (**text**)
            else if let boldRange = findMatchingPair(in: remaining, open: "**", close: "**") {
                if boldRange.lowerBound > remaining.startIndex {
                    let before = String(remaining[remaining.startIndex..<boldRange.lowerBound])
                    segments.append(contentsOf: parseBoldItalic(before, skipBold: true))
                }
                let boldContent = String(remaining[
                    remaining.index(boldRange.lowerBound, offsetBy: 2)..<boldRange.upperBound
                ])
                segments.append(.bold(boldContent))
                remaining = remaining[remaining.index(after: remaining.index(boldRange.upperBound, offsetBy: 1))...]
            }
            // Try italic (*text* or _text_)
            else if let italicRange = findMatchingPair(in: remaining, open: "*", close: "*") ??
                                     findMatchingPair(in: remaining, open: "_", close: "_") {
                if italicRange.lowerBound > remaining.startIndex {
                    let before = String(remaining[remaining.startIndex..<italicRange.lowerBound])
                    segments.append(.plain(before))
                }
                let italicContent = String(remaining[
                    remaining.index(after: italicRange.lowerBound)..<italicRange.upperBound
                ])
                segments.append(.italic(italicContent))
                remaining = remaining[remaining.index(after: italicRange.upperBound)...]
            }
            else {
                // No more markdown pairs found — emit remaining as plain
                // Hide trailing unclosed delimiters for a clean look
                let plainText = hideUnclosedDelimiters(String(remaining))
                if !plainText.isEmpty {
                    segments.append(.plain(plainText))
                }
                break
            }
        }

        return segments
    }

    /// Find a matching pair of delimiters in a string.
    /// Returns the range of the content between the delimiters (excluding the delimiters).
    private static func findMatchingPair(
        in text: Substring,
        open: String,
        close: String
    ) -> Range<Substring.Index>? {
        guard let openRange = text.range(of: open) else { return nil }
        let searchStart = text.index(openRange.upperBound, offsetBy: 0)
        guard searchStart < text.endIndex else { return nil }
        guard let closeRange = text.range(of: close, range: searchStart..<text.endIndex) else { return nil }
        // Return the range covering from open start to close end
        return openRange.lowerBound..<closeRange.upperBound
    }

    /// Parse bold and italic in a substring that doesn't contain code.
    private static func parseBoldItalic(_ text: String, skipBold: Bool = false) -> [StreamingSegment] {
        var segments: [StreamingSegment] = []
        var remaining = Substring(text)

        while !remaining.isEmpty {
            if !skipBold, let boldRange = findMatchingPair(in: remaining, open: "**", close: "**") {
                if boldRange.lowerBound > remaining.startIndex {
                    segments.append(.plain(String(remaining[remaining.startIndex..<boldRange.lowerBound])))
                }
                let boldContent = String(remaining[
                    remaining.index(boldRange.lowerBound, offsetBy: 2)..<boldRange.upperBound
                ])
                segments.append(.bold(boldContent))
                remaining = remaining[remaining.index(after: remaining.index(boldRange.upperBound, offsetBy: 1))...]
            } else if let italicRange = findMatchingPair(in: remaining, open: "*", close: "*") ??
                                        findMatchingPair(in: remaining, open: "_", close: "_") {
                if italicRange.lowerBound > remaining.startIndex {
                    segments.append(.plain(String(remaining[remaining.startIndex..<italicRange.lowerBound])))
                }
                let italicContent = String(remaining[
                    remaining.index(after: italicRange.lowerBound)..<italicRange.upperBound
                ])
                segments.append(.italic(italicContent))
                remaining = remaining[remaining.index(after: italicRange.upperBound)...]
            } else {
                let plain = hideUnclosedDelimiters(String(remaining))
                if !plain.isEmpty {
                    segments.append(.plain(plain))
                }
                break
            }
        }

        return segments
    }

    /// Hide unclosed markdown delimiters at the end of streaming text.
    /// This prevents the user from seeing raw ** or _ during generation.
    private static func hideUnclosedDelimiters(_ text: String) -> String {
        var result = text
        // Remove trailing unclosed bold delimiters
        while result.hasSuffix("**") && !result.hasPrefix("**") {
            result = String(result.dropLast(2))
        }
        // Remove trailing unclosed italic delimiters
        while result.hasSuffix("*") && result.count > 1 && !result.hasSuffix("**") {
            result = String(result.dropLast())
        }
        while result.hasSuffix("_") && result.count > 1 {
            // Only strip if it looks like an unclosed italic (odd number of _)
            let underscoreCount = result.filter { $0 == "_" }.count
            if underscoreCount % 2 != 0 {
                result = String(result.dropLast())
            } else {
                break
            }
        }
        // Remove trailing unclosed backtick
        while result.hasSuffix("`") && !result.hasSuffix("``") {
            result = String(result.dropLast())
        }
        return result
    }

    // MARK: - Finalized Rendering (Markdown)

    /// Render finalized text as rich markdown.
    ///
    /// Uses a segment-based approach:
    /// 1. Split text into code blocks and prose segments
    /// 2. Render code blocks with monospaced font + background
    /// 3. Render prose with AttributedString(markdown:) for inline formatting
    /// 4. Compose all segments into a single VStack
    ///
    /// If parsing fails (malformed markdown), falls back to plain text.
    ///
    /// - Parameter text: The complete, finalized message text.
    /// - Returns: A SwiftUI View with formatted markdown content.
    @ViewBuilder
    static func renderedText(_ text: String) -> some View {
        let segments = parseSegments(from: text)

        if segments.count == 1, case .prose(let content) = segments.first {
            // Simple case: no code blocks, just inline markdown
            renderInlineMarkdown(content)
        } else {
            // Complex case: mixed code blocks and prose
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    switch segment {
                    case .prose(let content):
                        if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            renderInlineMarkdown(content)
                        }
                    case .codeBlock(let language, let code):
                        renderCodeBlock(code, language: language)
                    }
                }
            }
        }
    }

    // MARK: - Inline Markdown Rendering

    /// Render a prose segment with AttributedString markdown parsing.
    ///
    /// Handles bold, italic, inline code, links, and strikethrough.
    @ViewBuilder
    private static func renderInlineMarkdown(_ text: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            Text(attributed)
                .font(.body)
        } else {
            // Fallback: plain text if markdown parsing fails
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Code Block Rendering

    /// Render a fenced code block with monospaced font and background.
    ///
    /// - Parameters:
    ///   - code: The code content (without the fencing backticks).
    ///   - language: The optional language tag (e.g., "swift", "python").
    @ViewBuilder
    private static func renderCodeBlock(_ code: String, language: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Language tag header
            if let language = language, !language.isEmpty {
                HStack {
                    Text(language)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(.systemGray5).opacity(0.7))
            }

            // Code content
            Text(code)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Segment Parsing

    /// A parsed segment of the message: either prose or a code block.
    enum MarkdownSegment {
        /// Prose text that may contain inline markdown (bold, italic, etc.)
        case prose(String)
        /// A fenced code block with optional language tag
        case codeBlock(language: String?, code: String)
    }

    /// Parse the text into segments of prose and code blocks.
    ///
    /// This handles the common pattern where LLM output contains
    /// fenced code blocks (```...```) mixed with explanatory prose.
    ///
    /// - Parameter text: The full message text.
    /// - Returns: Array of parsed segments.
    static func parseSegments(from text: String) -> [MarkdownSegment] {
        var segments: [MarkdownSegment] = []
        let lines = text.components(separatedBy: "\n")

        var inCodeBlock = false
        var codeBlockLanguage: String?
        var codeLines: [String] = []
        var proseLines: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if !inCodeBlock && trimmed.hasPrefix("```") {
                // Start of code block
                // Flush accumulated prose
                if !proseLines.isEmpty {
                    segments.append(.prose(proseLines.joined(separator: "\n")))
                    proseLines = []
                }

                inCodeBlock = true
                // Extract language tag: ```swift, ```python, etc.
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                codeBlockLanguage = lang.isEmpty ? nil : lang
                codeLines = []
            } else if inCodeBlock && trimmed.hasPrefix("```") {
                // End of code block
                inCodeBlock = false
                segments.append(.codeBlock(
                    language: codeBlockLanguage,
                    code: codeLines.joined(separator: "\n")
                ))
                codeBlockLanguage = nil
                codeLines = []
            } else if inCodeBlock {
                codeLines.append(line)
            } else {
                proseLines.append(line)
            }
        }

        // Flush remaining content
        if inCodeBlock {
            // Unclosed code block — include as code block anyway
            segments.append(.codeBlock(
                language: codeBlockLanguage,
                code: codeLines.joined(separator: "\n")
            ))
        } else if !proseLines.isEmpty {
            segments.append(.prose(proseLines.joined(separator: "\n")))
        }

        return segments
    }

    // MARK: - Code Block Detection

    /// Check if text contains code block markers (triple backticks).
    static func containsCodeBlocks(_ text: String) -> Bool {
        text.contains("```")
    }
}

// MARK: - Cursor View

/// A blinking cursor animation that appears during token streaming.
///
/// The cursor uses a repeating animation that fades in and out,
/// providing the classic "typing" indicator. It automatically
/// stops animating when the view disappears (SwiftUI lifecycle).
private struct CursorView: View {
    @State private var isVisible = true

    var body: some View {
        Text("\u{2588}") // Full block character
            .font(.body)
            .foregroundStyle(.secondary)
            .opacity(isVisible ? 1.0 : 0.0)
            .animation(
                .easeInOut(duration: 0.5)
                .repeatForever(autoreverses: true),
                value: isVisible
            )
            .onAppear {
                isVisible = false
            }
    }
}

// MARK: - Message Bubble Style

/// Visual style configuration for message bubbles.
///
/// Frutiger Aero edition: translucent colors designed to be overlaid on
/// frosted glass materials (.ultraThinMaterial / .regularMaterial).
///
/// - User bubbles: white tint on ultraThinMaterial for blue-tinted glass
/// - Assistant bubbles: white tint on regularMaterial for white-tinted glass
/// - Streaming bubbles: lighter tint for slightly more transparent look
enum MessageBubbleStyle {
    case user
    case assistant
    case streaming

    /// Background color for the bubble. Uses translucent colors that
    /// work with frosted glass material overlays for the Frutiger Aero look.
    var backgroundColor: Color {
        switch self {
        case .user:
            // White tint overlaid on ultraThinMaterial → blue-tinted glass
            Color.white.opacity(0.15)
        case .assistant:
            // White tint overlaid on regularMaterial → white-tinted glass
            Color.white.opacity(0.08)
        case .streaming:
            // Slightly more transparent for streaming
            Color.white.opacity(0.05)
        }
    }

    /// Foreground color for the text.
    var foregroundColor: Color {
        switch self {
        case .user:      return .primary
        case .assistant:  return .primary
        case .streaming:  return .primary
        }
    }

    /// Horizontal alignment for the bubble.
    var alignment: HorizontalAlignment {
        switch self {
        case .user:      return .trailing
        case .assistant:  return .leading
        case .streaming:  return .leading
        }
    }

    /// Maximum width for the bubble (in points). Constrains bubbles
    /// so they don't stretch across the full screen on iPad.
    var maxWidth: CGFloat {
        switch self {
        case .user:       return 300
        case .assistant:  return 340
        case .streaming:  return 340
        }
    }
}

// MARK: - Markdown Preview

/// A debug/preview view that shows both the raw markdown and the rendered version.
/// Useful during development to verify markdown parsing.
struct MarkdownPreviewView: View {
    let text: String
    @State private var showRaw = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Markdown Preview")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(showRaw ? "Rendered" : "Raw") {
                    showRaw.toggle()
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }

            if showRaw {
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            } else {
                MarkdownRenderer.renderedText(text)
                    .textSelection(.enabled)
            }
        }
        .padding()
    }
}
