//
//  BuiltInTools.swift
//  NeuraL
//
//  Phase 6.2 â€” Built-in Tools (Calculator, Calendar, Web Search)
//
//  These tools are registered at app launch and provide basic on-device
//  capabilities that the LLM can invoke during generation.
//

import Foundation
import UIKit

// MARK: - Calculator Tool

/// A simple math expression evaluator. Uses NSExpression for safe
/// evaluation of arithmetic expressions without arbitrary code execution.
struct CalculatorTool: NeuraLTool {
    let name = "calculator"
    let description = """
    Evaluates mathematical expressions. Supports basic arithmetic (+, -, *, /), \
    parentheses, and common math functions (sqrt, abs, ceil, floor, pow, log, sin, cos, tan). \
    Example: "2 + 2" returns 4, "sqrt(144)" returns 12.
    """

    var parameterSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "expression": [
                    "type": "string",
                    "description": "The mathematical expression to evaluate"
                ]
            ],
            "required": ["expression"]
        ]
    }

    func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let expression = parameters["expression"] as? String else {
            return .failure("Missing required parameter: expression")
        }

        // Sanitize: only allow numbers, operators, parentheses, and known functions
        let allowedChars = CharacterSet(charactersIn: "0123456789+-*/().,% ")
        let allowedFunctions = ["sqrt", "abs", "ceil", "floor", "pow", "log", "sin", "cos", "tan", "pi", "e"]

        var sanitized = expression.lowercased()
        // Replace common math notation
        sanitized = sanitized.replacingOccurrences(of: "x", with: "*")
        sanitized = sanitized.replacingOccurrences(of: "\u{00d7}", with: "*")
        sanitized = sanitized.replacingOccurrences(of: "\u{00f7}", with: "/")

        // Validate characters
        let filtered = sanitized.unicodeScalars.filter { allowedChars.contains($0) || CharacterSet.letters.contains($0) }
        let filteredStr = String(filtered)

        // Check for disallowed words (prevent code injection)
        let words = filteredStr.components(separatedBy: CharacterSet.letters.inverted)
        for word in words where !word.isEmpty {
            if !allowedFunctions.contains(word) && word.count > 1 {
                return .failure("Disallowed term in expression: '\(word)'. Only basic math functions are supported.")
            }
        }

        do {
            let expr = NSExpression(format: filteredStr)
            if let result = expr.expressionValue(with: nil, context: nil) {
                let number = NSNumber(value: 0)
                if let resultNum = result as? NSNumber, resultNum.compare(number) == .orderedSame && !(result is Bool) {
                    // It's a number
                    let doubleValue = (result as? NSNumber)?.doubleValue ?? 0
                    if doubleValue == floor(doubleValue) && abs(doubleValue) < Double(Int.max) {
                        return .success("Result: \(Int(doubleValue))")
                    } else {
                        return .success(String(format: "Result: %.6g", doubleValue))
                    }
                }
                return .success("Result: \(result)")
            } else {
                return .failure("Expression evaluated to nil")
            }
        } catch {
            return .failure("Could not evaluate expression: \(error.localizedDescription)")
        }
    }
}

// MARK: - Calendar Tool

/// Provides access to the device's calendar for date/time queries.
/// Does NOT access the user's calendar events (privacy-first).
struct CalendarTool: NeuraLTool {
    let name = "calendar"
    let description = """
    Returns the current date, time, and day of week. Can also calculate \
    date differences and format dates. Does NOT access personal calendar events.
    """

    var parameterSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "action": [
                    "type": "string",
                    "enum": ["now", "format", "difference"],
                    "description": "What to do: 'now' returns current date/time, 'format' formats a date, 'difference' calculates days between dates"
                ],
                "date": [
                    "type": "string",
                    "description": "Date in YYYY-MM-DD format (for format/difference actions)"
                ],
                "date2": [
                    "type": "string",
                    "description": "Second date for difference calculation (YYYY-MM-DD)"
                ],
                "format": [
                    "type": "string",
                    "description": "Date format string (e.g., 'MMMM d, yyyy')"
                ]
            ],
            "required": ["action"]
        ]
    }

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        return f
    }()

    func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let action = parameters["action"] as? String else {
            return .failure("Missing required parameter: action")
        }

        switch action {
        case "now":
            let now = Date()
            dateFormatter.dateStyle = .full
            dateFormatter.timeStyle = .long
            let formatted = dateFormatter.string(from: now)

            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: now)
            let weekday = calendar.weekdaySymbols[max(0, (components.weekday ?? 1) - 1)]

            return .success("Current date and time: \(formatted)\nDay of week: \(weekday)\nISO 8601: \(ISO8601DateFormatter().string(from: now))")

        case "format":
            guard let dateString = parameters["date"] as? String else {
                return .failure("Missing 'date' parameter for format action")
            }

            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withFullDate]
            guard let date = isoFormatter.date(from: dateString) ??
                    dateFormatter.date(from: dateString) else {
                return .failure("Could not parse date: \(dateString). Use YYYY-MM-DD format.")
            }

            let formatStr = parameters["format"] as? String ?? "MMMM d, yyyy"
            dateFormatter.dateFormat = formatStr
            return .success("Formatted date: \(dateFormatter.string(from: date))")

        case "difference":
            guard let dateStr1 = parameters["date"] as? String,
                  let dateStr2 = parameters["date2"] as? String else {
                return .failure("Missing 'date' and 'date2' parameters for difference action")
            }

            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withFullDate]

            guard let d1 = isoFormatter.date(from: dateStr1) ?? dateFormatter.date(from: dateStr1),
                  let d2 = isoFormatter.date(from: dateStr2) ?? dateFormatter.date(from: dateStr2) else {
                return .failure("Could not parse one or both dates. Use YYYY-MM-DD format.")
            }

            let days = Calendar.current.dateComponents([.day], from: d1, to: d2).day ?? 0
            let absDays = abs(days)
            let direction = days >= 0 ? "after" : "before"

            return .success("\(absDays) days \(direction) the first date (from \(dateStr1) to \(dateStr2): \(days) days)")

        default:
            return .failure("Unknown calendar action: \(action). Use 'now', 'format', or 'difference'.")
        }
    }
}

// MARK: - Device Info Tool

/// Returns basic device information that might be useful in context.
struct DeviceInfoTool: NeuraLTool {
    let name = "device_info"
    let description = """
    Returns information about the current device (model, OS version, screen size). \
    Useful for providing device-specific recommendations.
    """

    var parameterSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "category": [
                    "type": "string",
                    "enum": ["basic", "display", "storage"],
                    "description": "Which device info category to return"
                ]
            ]
        ]
    }

    func execute(parameters: [String: Any]) async throws -> ToolResult {
        let category = parameters["category"] as? String ?? "basic"
        let processInfo = ProcessInfo.processInfo

        switch category {
        case "basic":
            var info: [String] = []
            info.append("Device: \(UIDevice.current.model)")
            info.append("System: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
            info.append("Processor cores: \(processInfo.processorCount)")
            info.append("Physical memory: \(String(format: "%.1f GB", Double(processInfo.physicalMemory) / 1_073_741_824))")
            let isLowPower = processInfo.isLowPowerModeEnabled
            info.append("Low power mode: \(isLowPower ? "Yes" : "No")")
            return .success(info.joined(separator: "\n"))

        case "display":
            let screen = UIScreen.main
            var info: [String] = []
            info.append(String(format: "Screen: %.0f x %.0f points", screen.bounds.width, screen.bounds.height))
            info.append(String(format: "Scale: %.1fx", screen.scale))
            info.append(String(format: "Pixel size: %.0f x %.0f", screen.bounds.width * screen.scale, screen.bounds.height * screen.scale))
            return .success(info.joined(separator: "\n"))

        case "storage":
            let fileURL = URL(fileURLWithPath: NSHomeDirectory())
            if let values = try? fileURL.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
                let total = Double(values.volumeTotalCapacity ?? 0) / 1_073_741_824
                let available = Double(values.volumeAvailableCapacityForImportantUsage ?? 0) / 1_073_741_824
                return .success(String(format: "Total storage: %.1f GB\nAvailable: %.1f GB (%.0f%% used)", total, available, ((total - available) / total) * 100))
            }
            return .failure("Could not retrieve storage information")

        default:
            return .failure("Unknown category: \(category). Use 'basic', 'display', or 'storage'.")
        }
    }
}

// MARK: - Tool Registration Helper

/// Register all built-in tools with the shared registry.
enum BuiltInTools {
    static func registerAll() async {
        let registry = ToolRegistry.shared
        await registry.register(CalculatorTool())
        await registry.register(CalendarTool())
        await registry.register(DeviceInfoTool())
    }
}

