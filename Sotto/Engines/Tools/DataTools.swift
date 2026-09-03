import Foundation

/// The six data built-ins: JSON, CSV, descriptive statistics, percentages and number bases.
enum DataTools {
    // MARK: - format_json

    static let jsonStyles = ["pretty", "minified"]

    static func formatJSON(_ arguments: [String: Any]) throws -> String {
        let source = try ToolArguments.text(arguments, "json")
        let style = try ToolArguments.choice(arguments, "style", from: jsonStyles, fallback: "pretty")
        let value = try parseJSON(source)
        var options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
        if style == "pretty" { options.insert(.prettyPrinted) }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: options) else {
            throw ToolExecutionError.invalidArguments("that JSON could not be written back out")
        }
        return "Valid JSON, \(style):\n" + String(decoding: data, as: UTF8.self)
    }

    /// Reads JSON and turns a parse failure into a sentence naming what went wrong.
    static func parseJSON(_ source: String) throws -> Any {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ToolExecutionError.invalidArguments("the JSON is empty") }
        guard let data = trimmed.data(using: .utf8) else {
            throw ToolExecutionError.invalidArguments("the JSON is not valid UTF-8")
        }
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            let reason = (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String
            throw ToolExecutionError.invalidArguments("that is not valid JSON — \(reason ?? error.localizedDescription)")
        }
    }

    // MARK: - query_json

    static func queryJSON(_ arguments: [String: Any]) throws -> String {
        let source = try ToolArguments.text(arguments, "json")
        let path = try ToolArguments.text(arguments, "path").trimmingCharacters(in: .whitespaces)
        var node = try parseJSON(source)
        var walked: [String] = []
        for component in path.split(separator: ".").map(String.init) where !component.isEmpty {
            if let dictionary = node as? [String: Any], let next = dictionary[component] {
                node = next
            } else if let array = node as? [Any], let index = Int(component), array.indices.contains(index) {
                node = array[index]
            } else {
                let reached = walked.isEmpty ? "the top level" : "“\(walked.joined(separator: "."))”"
                return "No value at “\(path)”: \(reached) has no “\(component)”."
            }
            walked.append(component)
        }
        let label = path.isEmpty ? "the whole document" : "“\(path)”"
        return "\(label) is \(describeJSON(node))"
    }

    static func describeJSON(_ node: Any) -> String {
        switch node {
        case is NSNull: return "null"
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            return ToolTemplate.displayString(number)
        case let text as String: return "\"\(text)\""
        case let array as [Any]:
            let encoded = (try? JSONSerialization.data(withJSONObject: array, options: [.prettyPrinted, .withoutEscapingSlashes]))
                .map { String(decoding: $0, as: UTF8.self) } ?? "\(array)"
            return "an array of \(array.count) item\(array.count == 1 ? "" : "s"):\n\(encoded)"
        case let object as [String: Any]:
            let encoded = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]))
                .map { String(decoding: $0, as: UTF8.self) } ?? "\(object)"
            return "an object with \(object.count) key\(object.count == 1 ? "" : "s"):\n\(encoded)"
        default: return "\(node)"
        }
    }

    // MARK: - summarize_csv

    static func summariseCSV(_ arguments: [String: Any]) throws -> String {
        let source = try ToolArguments.text(arguments, "csv")
        let delimiterText = try ToolArguments.text(arguments, "delimiter", fallback: ",")
        guard let delimiter = delimiterText.first, delimiterText.count == 1 else {
            throw ToolExecutionError.invalidArguments("“delimiter” must be a single character")
        }
        let hasHeader = ToolArguments.flag(arguments, "has_header", fallback: true)
        let rows = parseCSV(source, delimiter: delimiter)
        guard let first = rows.first else { throw ToolExecutionError.invalidArguments("the CSV has no rows") }
        let headers = hasHeader ? first : (0..<first.count).map { "column \($0 + 1)" }
        let body = hasHeader ? Array(rows.dropFirst()) : rows
        var lines = ["\(Format.integer(body.count)) data row\(body.count == 1 ? "" : "s"), \(headers.count) column\(headers.count == 1 ? "" : "s")"]
        for (index, header) in headers.enumerated() {
            lines.append(columnSummary(header: header, values: body.compactMap { index < $0.count ? $0[index] : nil }))
        }
        return lines.joined(separator: "\n")
    }

    private static func columnSummary(header: String, values: [String]) -> String {
        let filled = values.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let numbers = filled.compactMap { Double($0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")) }
        let blanks = values.count - filled.count
        let blankNote = blanks > 0 ? ", \(blanks) blank" : ""
        if !numbers.isEmpty, numbers.count == filled.count {
            let total = numbers.reduce(0, +)
            let minimum = numbers.min() ?? 0
            let maximum = numbers.max() ?? 0
            return "- \(header): numeric\(blankNote) — min \(BuiltInTools.formatNumber(minimum)), max \(BuiltInTools.formatNumber(maximum)), mean \(BuiltInTools.formatNumber(rounded(total / Double(numbers.count)))), sum \(BuiltInTools.formatNumber(rounded(total)))"
        }
        let distinct = Set(filled).count
        return "- \(header): text\(blankNote) — \(distinct) distinct value\(distinct == 1 ? "" : "s")"
    }

    /// RFC 4180-style parsing: quoted fields may hold the delimiter, newlines, and doubled quotes.
    static func parseCSV(_ source: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = source.makeIterator()
        var pending: Character?
        while let character = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }
            switch character {
            case "\"" where field.isEmpty: inQuotes = true
            case delimiter:
                row.append(field)
                field = ""
            case "\n", "\r\n", "\r":
                row.append(field)
                field = ""
                if row.contains(where: { !$0.isEmpty }) || row.count > 1 { rows.append(row) }
                row = []
            default: field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    // MARK: - describe_numbers

    static func describeNumbers(_ arguments: [String: Any]) throws -> String {
        let source = try ToolArguments.text(arguments, "numbers")
        let values = source
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0.isWhitespace || $0.isNewline })
            .compactMap { Double($0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))) }
        guard !values.isEmpty else {
            throw ToolExecutionError.invalidArguments("no numbers were found in “\(source.prefix(40))”")
        }
        let sorted = values.sorted()
        let total = values.reduce(0, +)
        let mean = total / Double(values.count)
        let median = sorted.count % 2 == 1
            ? sorted[sorted.count / 2]
            : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        let deviation = values.count > 1
            ? (values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count - 1)).squareRoot()
            : 0
        return """
        \(values.count) numbers
        sum \(BuiltInTools.formatNumber(rounded(total))), mean \(BuiltInTools.formatNumber(rounded(mean))), median \(BuiltInTools.formatNumber(rounded(median)))
        min \(BuiltInTools.formatNumber(sorted[0])), max \(BuiltInTools.formatNumber(sorted[sorted.count - 1])), range \(BuiltInTools.formatNumber(rounded(sorted[sorted.count - 1] - sorted[0])))
        standard deviation \(BuiltInTools.formatNumber(rounded(deviation))) (sample)
        """
    }

    // MARK: - percentage

    static let percentModes = ["percent_of", "what_percent", "change", "increase", "decrease"]

    static func percentage(_ arguments: [String: Any]) throws -> String {
        let mode = try ToolArguments.choice(arguments, "mode", from: percentModes)
        let value = try ToolArguments.number(arguments, "value")
        let other = try ToolArguments.number(arguments, "other")
        switch mode {
        case "percent_of":
            return "\(BuiltInTools.formatNumber(value))% of \(BuiltInTools.formatNumber(other)) = \(BuiltInTools.formatNumber(rounded(value / 100 * other)))"
        case "what_percent":
            guard other != 0 else { throw ToolExecutionError.invalidArguments("“other” cannot be zero for what_percent") }
            return "\(BuiltInTools.formatNumber(value)) is \(BuiltInTools.formatNumber(rounded(value / other * 100)))% of \(BuiltInTools.formatNumber(other))"
        case "change":
            guard value != 0 else { throw ToolExecutionError.invalidArguments("“value” cannot be zero for change") }
            let delta = (other - value) / abs(value) * 100
            let word = delta < 0 ? "decrease" : "increase"
            return "\(BuiltInTools.formatNumber(value)) → \(BuiltInTools.formatNumber(other)) is a \(BuiltInTools.formatNumber(rounded(abs(delta))))% \(word)"
        case "increase":
            return "\(BuiltInTools.formatNumber(value)) increased by \(BuiltInTools.formatNumber(other))% = \(BuiltInTools.formatNumber(rounded(value * (1 + other / 100))))"
        default:
            return "\(BuiltInTools.formatNumber(value)) decreased by \(BuiltInTools.formatNumber(other))% = \(BuiltInTools.formatNumber(rounded(value * (1 - other / 100))))"
        }
    }

    // MARK: - convert_base

    static func convertBase(_ arguments: [String: Any]) throws -> String {
        let raw = try ToolArguments.text(arguments, "value").trimmingCharacters(in: .whitespaces)
        let from = ToolArguments.integer(arguments, "from_base", fallback: 10, in: 2...36)
        let to = ToolArguments.integer(arguments, "to_base", fallback: 2, in: 2...36)
        let cleaned = raw.replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "0x", with: "", options: [.caseInsensitive, .anchored])
            .replacingOccurrences(of: "0b", with: "", options: [.caseInsensitive, .anchored])
        let negative = cleaned.hasPrefix("-")
        let digits = negative ? String(cleaned.dropFirst()) : cleaned
        guard !digits.isEmpty, let magnitude = Int64(digits, radix: from) else {
            throw ToolExecutionError.invalidArguments("“\(raw)” is not a base-\(from) number")
        }
        let converted = String(magnitude, radix: to).uppercased()
        let sign = negative ? "-" : ""
        return "\(raw) in base \(from) = \(sign)\(converted) in base \(to) (decimal \(sign)\(magnitude))"
    }

    /// Trims floating-point noise so 0.1 + 0.2 does not surface as 0.30000000000000004.
    static func rounded(_ value: Double) -> Double {
        guard value.isFinite else { return value }
        return (value * 1_000_000).rounded() / 1_000_000
    }
}
