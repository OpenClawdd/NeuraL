//
//  ToolRegistry.swift
//  NeuraL
//
//  Phase 6.2 — Function Calling / Tool Use System
//
//  Provides a registry for tools that the LLM can invoke during generation.
//  The system works by:
//
//  1. Registering tools with their JSON schemas (name, description, parameters)
//  2. Including tool definitions in the system prompt or special tokens
//  3. Parsing the model's output for function call blocks (JSON format)
//  4. Executing the function call and injecting the result back into context
//  5. Continuing generation with the tool result available
//
//  This follows the ReAct (Reasoning + Acting) pattern commonly used in
//  tool-augmented LLM applications.
//

import Foundation

// MARK: - Tool Protocol

/// Protocol that all NeuraL tools must conform to.
///
/// Tools are registered with the ToolRegistry and made available to the
/// LLM during generation. When the model outputs a function call block,
/// the ToolExecutor parses it, finds the matching tool, executes it,
/// and returns the result.
protocol NeuraLTool: Sendable {
    /// Unique identifier for this tool (e.g., "calculator").
    var name: String { get }
    /// Human-readable description shown to the model in the system prompt.
    var description: String { get }
    /// JSON Schema for the tool's parameters.
    var parameterSchema: [String: Any] { get }
    /// Execute the tool with the given parameters.
    func execute(parameters: [String: Any]) async throws -> ToolResult
}

// MARK: - Tool Result

/// The result of a tool execution.
struct ToolResult: Sendable {
    /// The output text to inject back into the conversation.
    let output: String
    /// Whether the execution was successful.
    let isSuccess: Bool
    /// Optional metadata about the execution (timing, sources, etc.).
    let metadata: [String: String]

    static func success(_ output: String, metadata: [String: String] = [:]) -> ToolResult {
        ToolResult(output: output, isSuccess: true, metadata: metadata)
    }

    static func failure(_ error: String) -> ToolResult {
        ToolResult(output: error, isSuccess: false, metadata: [:])
    }
}

// MARK: - Function Call

/// A parsed function call from the model's output.
struct FunctionCall: Sendable {
    /// The name of the tool to call.
    let name: String
    /// The parameters to pass to the tool.
    let parameters: [String: Any]
    /// The raw text that was parsed (for display in the UI).
    let rawText: String

    /// Convert parameters to a JSON string for display.
    var parametersJSON: String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: parameters,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

// MARK: - Tool Registry

/// Central registry for all available tools. Tools are registered at
/// app launch and looked up by name when the model requests a function call.
actor ToolRegistry {

    static let shared = ToolRegistry()

    private var tools: [String: any NeuraLTool] = [:]

    /// Register a tool with the registry.
    func register(_ tool: any NeuraLTool) {
        tools[tool.name] = tool
    }

    /// Unregister a tool by name.
    func unregister(name: String) {
        tools.removeValue(forKey: name)
    }

    /// Look up a tool by name.
    func tool(named name: String) -> (any NeuraLTool)? {
        tools[name]
    }

    /// Get all registered tools.
    func allTools() -> [any NeuraLTool] {
        Array(tools.values)
    }

    /// Generate the tool definitions section for the system prompt.
    /// This tells the model what tools are available and how to call them.
    func generateToolDefinitionsPrompt() -> String {
        guard !tools.isEmpty else { return "" }

        var parts: [String] = []
        parts.append("You have access to the following tools. To call a tool, output a JSON block in the following format:")
        parts.append("")
        parts.append("<function>")
        parts.append("{\"name\": \"tool_name\", \"parameters\": {\"param1\": \"value1\"}}")
        parts.append("</function>")
        parts.append("")
        parts.append("Available tools:")
        parts.append("")

        for tool in tools.values {
            parts.append("### \(tool.name)")
            parts.append(tool.description)
            parts.append("")

            if let schemaData = try? JSONSerialization.data(
                withJSONObject: tool.parameterSchema,
                options: [.prettyPrinted, .sortedKeys]
            ), let schemaStr = String(data: schemaData, encoding: .utf8) {
                parts.append("Parameters schema:")
                parts.append("```json")
                parts.append(schemaStr)
                parts.append("```")
            }
            parts.append("")
        }

        parts.append("Only call tools when they are necessary to answer the user's question. If you can answer directly, do so without using tools.")

        return parts.joined(separator: "\n")
    }
}

// MARK: - Function Call Parser

/// Parses function call blocks from model output text.
///
/// The expected format is:
/// ```
/// <function>
/// {"name": "calculator", "parameters": {"expression": "2+2"}}
/// </function>
/// ```
///
/// The parser handles:
/// - Multiple function calls in a single response
/// - Malformed JSON (graceful degradation)
/// - Partial function blocks (during streaming)
enum FunctionCallParser {

    /// Parse all complete function call blocks from text.
    static func parseCalls(from text: String) -> [FunctionCall] {
        var calls: [FunctionCall] = []
        let openTag = "<function>"
        let closeTag = "</function>"

        var searchStart = text.startIndex
        while let openRange = text.range(of: openTag, range: searchStart..<text.endIndex) {
            guard let closeRange = text.range(of: closeTag, range: openRange.upperBound..<text.endIndex) else {
                break // Incomplete function block
            }

            let jsonContent = String(text[openRange.upperBound..<closeRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let jsonData = jsonContent.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let name = json["name"] as? String {

                let parameters = json["parameters"] as? [String: Any] ?? [:]
                let rawText = String(text[openRange.lowerBound..<closeRange.upperBound])

                calls.append(FunctionCall(
                    name: name,
                    parameters: parameters,
                    rawText: rawText
                ))
            }

            searchStart = closeRange.upperBound
        }

        return calls
    }

    /// Check if text contains a partial (incomplete) function call block.
    /// Used during streaming to detect when the model is generating a function call.
    static func hasPartialFunctionCall(in text: String) -> Bool {
        let openTag = "<function>"
        let closeTag = "</function>"

        guard let lastOpen = text.range(of: openTag, options: .backwards) else {
            return false
        }

        // Check if there's a closing tag after the last opening tag
        let afterOpen = text[lastOpen.upperBound...]
        return !afterOpen.contains(closeTag)
    }

    /// Strip function call blocks from text, leaving only the prose content.
    static func stripFunctionCalls(from text: String) -> String {
        let openTag = "<function>"
        let closeTag = "</function>"

        var result = text
        while let openRange = result.range(of: openTag),
              let closeRange = result.range(of: closeTag, range: openRange.upperBound..<result.endIndex) {
            result.removeSubrange(openRange.lowerBound..<closeRange.upperBound)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Tool Executor

/// Executes function calls by finding the matching tool in the registry
/// and running it with the parsed parameters.
actor ToolExecutor {

    private let registry: ToolRegistry

    init(registry: ToolRegistry = .shared) {
        self.registry = registry
    }

    /// Execute a function call.
    func execute(call: FunctionCall) async -> ToolResult {
        guard let tool = await registry.tool(named: call.name) else {
            return .failure("Unknown tool: \(call.name). Available tools: \(await registry.allTools().map(\.name).joined(separator: ", "))")
        }

        do {
            return try await tool.execute(parameters: call.parameters)
        } catch {
            return .failure("Tool '\(call.name)' execution failed: \(error.localizedDescription)")
        }
    }

    /// Execute multiple function calls in sequence.
    func executeAll(calls: [FunctionCall]) async -> [ToolResult] {
        var results: [ToolResult] = []
        for call in calls {
            let result = await execute(call: call)
            results.append(result)
        }
        return results
    }
}
