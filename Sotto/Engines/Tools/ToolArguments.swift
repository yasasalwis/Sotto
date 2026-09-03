import Foundation

/// Reads the arguments a model chose for a built-in tool.
///
/// Every built-in validates its own arguments through this type so a missing or nonsensical value
/// produces the same sentence wherever it happens, and so each tool function stays small. The
/// generic required-parameter check in `ToolExecutor.validate` runs first; this adds the per-tool
/// meaning, such as "that is not one of the styles I know".
enum ToolArguments {
    /// Longest text a built-in will process. Well above anything a model writes, and low enough
    /// that the line-by-line tools stay fast on a phone.
    static let maximumTextCharacters = 100_000

    static func text(_ arguments: [String: Any], _ key: String) throws -> String {
        guard let value = ToolTemplate.stringValue(arguments[key]) else {
            throw ToolExecutionError.invalidArguments("“\(key)” is required and must be text")
        }
        guard value.count <= maximumTextCharacters else {
            throw ToolExecutionError.invalidArguments("“\(key)” is longer than \(Format.integer(maximumTextCharacters)) characters")
        }
        return value
    }

    /// Text that may be absent, in which case `fallback` is used.
    static func text(_ arguments: [String: Any], _ key: String, fallback: String) throws -> String {
        guard arguments[key] != nil, !(arguments[key] is NSNull) else { return fallback }
        let value = try text(arguments, key)
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : value
    }

    static func number(_ arguments: [String: Any], _ key: String) throws -> Double {
        guard let value = ToolTemplate.doubleValue(arguments[key]), value.isFinite else {
            throw ToolExecutionError.invalidArguments("“\(key)” is required and must be a number")
        }
        return value
    }

    /// A whole number clamped into `range`, falling back when the model left it out.
    static func integer(_ arguments: [String: Any], _ key: String, fallback: Int, in range: ClosedRange<Int>) -> Int {
        guard let value = ToolTemplate.doubleValue(arguments[key]), value.isFinite else { return fallback }
        return min(max(Int(value.rounded()), range.lowerBound), range.upperBound)
    }

    static func flag(_ arguments: [String: Any], _ key: String, fallback: Bool) -> Bool {
        switch arguments[key] {
        case let number as NSNumber: return number.boolValue
        case let text as String:
            let lowered = text.trimmingCharacters(in: .whitespaces).lowercased()
            if ["true", "yes", "1", "on"].contains(lowered) { return true }
            if ["false", "no", "0", "off"].contains(lowered) { return false }
            return fallback
        default: return fallback
        }
    }

    /// One of a fixed set of words. Models write "Title Case" and "title-case" for the same thing,
    /// so the comparison ignores case, spaces, hyphens and underscores.
    static func choice(_ arguments: [String: Any], _ key: String, from options: [String], fallback: String? = nil) throws -> String {
        guard let raw = ToolTemplate.stringValue(arguments[key])?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            if let fallback { return fallback }
            throw ToolExecutionError.invalidArguments("“\(key)” is required; use one of \(options.joined(separator: ", "))")
        }
        let needle = normalise(raw)
        guard let match = options.first(where: { normalise($0) == needle }) else {
            throw ToolExecutionError.invalidArguments("“\(raw)” is not a \(key) I know; use one of \(options.joined(separator: ", "))")
        }
        return match
    }

    private static func normalise(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
