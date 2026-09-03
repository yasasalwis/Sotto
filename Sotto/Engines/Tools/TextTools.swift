import Foundation

/// The six text built-ins. All of them are pure functions of their arguments, so a model can be
/// held to what they return, and none of them touch the network or the file system.
enum TextTools {
    // MARK: - transform_text

    static let styles = [
        "upper", "lower", "title", "sentence", "snake", "kebab",
        "camel", "pascal", "slug", "trim", "reverse", "strip_accents",
    ]

    static func transform(_ arguments: [String: Any]) throws -> String {
        let text = try ToolArguments.text(arguments, "text")
        let style = try ToolArguments.choice(arguments, "style", from: styles)
        let result = transform(text, style: style)
        return result.isEmpty ? "(the transformed text is empty)" : result
    }

    static func transform(_ text: String, style: String) -> String {
        switch style {
        case "upper": return text.uppercased()
        case "lower": return text.lowercased()
        case "title": return words(in: text).map { capitalisedFirst($0) }.joined(separator: " ")
        case "sentence": return sentenceCase(text)
        case "snake": return words(in: text).map { $0.lowercased() }.joined(separator: "_")
        case "kebab", "slug": return words(in: text).map { $0.lowercased() }.joined(separator: "-")
        case "camel": return camel(text, capitaliseFirst: false)
        case "pascal": return camel(text, capitaliseFirst: true)
        case "trim": return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case "reverse": return String(text.reversed())
        default: return text.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        }
    }

    /// Splits on anything that is not a letter or a number, and also at lower→upper boundaries so
    /// "toolExecutor" becomes two words rather than one.
    static func words(in text: String) -> [String] {
        var output: [String] = []
        var current = ""
        var previous: Character?
        for character in text {
            guard character.isLetter || character.isNumber else {
                if !current.isEmpty { output.append(current); current = "" }
                previous = nil
                continue
            }
            if let previous, previous.isLowercase, character.isUppercase, !current.isEmpty {
                output.append(current)
                current = ""
            }
            current.append(character)
            previous = character
        }
        if !current.isEmpty { output.append(current) }
        return output
    }

    private static func capitalisedFirst(_ word: String) -> String {
        guard let first = word.first else { return word }
        return first.uppercased() + word.dropFirst().lowercased()
    }

    private static func camel(_ text: String, capitaliseFirst: Bool) -> String {
        let parts = words(in: text)
        return parts.enumerated().map { index, word in
            index == 0 && !capitaliseFirst ? word.lowercased() : capitalisedFirst(word)
        }.joined()
    }

    private static func sentenceCase(_ text: String) -> String {
        var output = ""
        var startOfSentence = true
        for character in text.lowercased() {
            if startOfSentence, character.isLetter {
                output += character.uppercased()
                startOfSentence = false
            } else {
                output.append(character)
                if ".!?".contains(character) { startOfSentence = true }
            }
        }
        return output
    }

    // MARK: - replace_text

    /// Literal find-and-replace. Deliberately not a regular expression: a pattern chosen by a
    /// model can backtrack for minutes on an innocent string, and built-ins run without a timeout.
    static func replace(_ arguments: [String: Any]) throws -> String {
        let text = try ToolArguments.text(arguments, "text")
        let find = try ToolArguments.text(arguments, "find")
        let replacement = try ToolArguments.text(arguments, "replace", fallback: "")
        guard !find.isEmpty else { throw ToolExecutionError.invalidArguments("“find” cannot be empty") }
        let matchCase = ToolArguments.flag(arguments, "match_case", fallback: true)
        let options: String.CompareOptions = matchCase ? [.literal] : [.caseInsensitive]
        var count = 0
        var searchStart = text.startIndex
        while let range = text.range(of: find, options: options, range: searchStart..<text.endIndex) {
            count += 1
            searchStart = range.upperBound > range.lowerBound ? range.upperBound : text.index(after: range.lowerBound)
            if searchStart >= text.endIndex { break }
        }
        guard count > 0 else { return "“\(find)” does not appear in the text. Nothing was changed." }
        let result = text.replacingOccurrences(of: find, with: replacement, options: options)
        return "\(count) replacement\(count == 1 ? "" : "s"):\n\(result)"
    }

    // MARK: - extract_matches

    static let matchKinds = ["email", "url", "number", "hashtag", "mention", "ip_address", "date", "phone"]

    /// Fixed patterns, audited to have no nested quantifier, so no input can make them run long.
    private static let patterns: [String: String] = [
        "email": "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}",
        "number": "-?[0-9]+(?:\\.[0-9]+)?",
        // The lookbehind keeps the "@" of an email address out of the mention results, and the
        // "#" of a URL fragment out of the hashtags.
        "hashtag": "(?<![A-Za-z0-9_])#[A-Za-z0-9_]+",
        "mention": "(?<![A-Za-z0-9._%+-])@[A-Za-z0-9_]+",
        "ip_address": "\\b(?:[0-9]{1,3}\\.){3}[0-9]{1,3}\\b",
    ]

    static func extract(_ arguments: [String: Any]) throws -> String {
        let text = try ToolArguments.text(arguments, "text")
        let kind = try ToolArguments.choice(arguments, "kind", from: matchKinds)
        let limit = ToolArguments.integer(arguments, "limit", fallback: 25, in: 1...100)
        let found = try matches(of: kind, in: text)
        guard !found.isEmpty else { return "No \(kind.replacingOccurrences(of: "_", with: " ")) found in the text." }
        let shown = found.prefix(limit)
        let header = "\(found.count) \(kind.replacingOccurrences(of: "_", with: " ")) match\(found.count == 1 ? "" : "es")"
        let suffix = found.count > shown.count ? " (first \(shown.count) shown)" : ""
        return header + suffix + ":\n" + shown.map { "- \($0)" }.joined(separator: "\n")
    }

    static func matches(of kind: String, in text: String) throws -> [String] {
        if let pattern = patterns[kind] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                throw ToolExecutionError.invalidArguments("the \(kind) pattern could not be prepared")
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.matches(in: text, range: range).compactMap { match in
                Range(match.range, in: text).map { String(text[$0]) }
            }
        }
        let types: NSTextCheckingResult.CheckingType
        switch kind {
        case "url": types = .link
        case "date": types = .date
        default: types = .phoneNumber
        }
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    // MARK: - sort_lines

    static let orders = ["ascending", "descending", "longest", "shortest", "reverse"]

    static func sortLines(_ arguments: [String: Any]) throws -> String {
        let text = try ToolArguments.text(arguments, "text")
        let order = try ToolArguments.choice(arguments, "order", from: orders, fallback: "ascending")
        let dropDuplicates = ToolArguments.flag(arguments, "unique", fallback: false)
        var lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let original = lines.count
        guard original > 0 else { return "The text has no lines to sort." }
        if dropDuplicates {
            var seen = Set<String>()
            lines = lines.filter { seen.insert($0.trimmingCharacters(in: .whitespaces)).inserted }
        }
        switch order {
        case "descending": lines.sort { $0.localizedStandardCompare($1) == .orderedDescending }
        case "longest": lines.sort { $0.count > $1.count }
        case "shortest": lines.sort { $0.count < $1.count }
        case "reverse": lines.reverse()
        default: lines.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        }
        let removed = original - lines.count
        let note = removed > 0 ? " after removing \(removed) duplicate\(removed == 1 ? "" : "s")" : ""
        return "\(lines.count) line\(lines.count == 1 ? "" : "s")\(note), sorted \(order):\n" + lines.joined(separator: "\n")
    }

    // MARK: - word_frequency

    /// Words too common to be interesting in a frequency count. Short and English-only on purpose:
    /// a longer list starts throwing away words the user cared about.
    static let commonWords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "if", "of", "to", "in", "on", "at", "for", "with",
        "is", "are", "was", "were", "be", "been", "being", "it", "its", "this", "that", "these",
        "those", "as", "by", "from", "not", "no", "so", "than", "then", "there", "their", "they",
        "you", "your", "we", "our", "i", "he", "she", "his", "her", "have", "has", "had", "do",
        "does", "did", "will", "would", "can", "could", "should", "about", "into", "over", "all",
    ]

    static func wordFrequency(_ arguments: [String: Any]) throws -> String {
        let text = try ToolArguments.text(arguments, "text")
        let limit = ToolArguments.integer(arguments, "limit", fallback: 10, in: 1...50)
        let skipCommon = ToolArguments.flag(arguments, "ignore_common", fallback: true)
        let tokens = text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
            .filter { !$0.isEmpty && (!skipCommon || !commonWords.contains($0)) }
        guard !tokens.isEmpty else { return "No countable words were found in the text." }
        let counts = tokens.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        let ranked = counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(limit)
        let total = tokens.count
        let lines = ranked.map { word, count in
            "- \(word): \(count) (\(Format.percent(Double(count) / Double(total))))"
        }
        let scope = skipCommon ? " excluding common words" : ""
        return "\(Format.integer(total)) words counted\(scope), \(counts.count) distinct. Most frequent:\n" + lines.joined(separator: "\n")
    }

    // MARK: - compare_texts

    /// Lines compared per side. Beyond this the diff table costs more memory than the answer is
    /// worth on a phone, so the comparison stops and says so.
    static let maximumDiffLines = 800

    static func compare(_ arguments: [String: Any]) throws -> String {
        let first = try ToolArguments.text(arguments, "first").components(separatedBy: .newlines)
        let second = try ToolArguments.text(arguments, "second").components(separatedBy: .newlines)
        guard first.count <= maximumDiffLines, second.count <= maximumDiffLines else {
            throw ToolExecutionError.invalidArguments("each text must be \(maximumDiffLines) lines or fewer to compare")
        }
        let changes = diff(first, second)
        let removed = changes.filter { $0.0 == "-" }.count
        let added = changes.filter { $0.0 == "+" }.count
        guard removed + added > 0 else { return "The two texts are identical: \(first.count) line\(first.count == 1 ? "" : "s")." }
        let shown = changes.prefix(60).map { "\($0.0) \($0.1)" }
        let suffix = changes.count > shown.count ? "\n… \(changes.count - shown.count) more changed lines" : ""
        return "\(removed) line\(removed == 1 ? "" : "s") only in the first text, \(added) only in the second:\n"
            + shown.joined(separator: "\n") + suffix
    }

    /// Longest-common-subsequence diff, returning only the lines that differ.
    static func diff(_ first: [String], _ second: [String]) -> [(String, String)] {
        var table = [[Int]](repeating: [Int](repeating: 0, count: second.count + 1), count: first.count + 1)
        for i in stride(from: first.count - 1, through: 0, by: -1) {
            for j in stride(from: second.count - 1, through: 0, by: -1) {
                table[i][j] = first[i] == second[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var output: [(String, String)] = []
        var i = 0
        var j = 0
        while i < first.count, j < second.count {
            if first[i] == second[j] {
                i += 1
                j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                output.append(("-", first[i]))
                i += 1
            } else {
                output.append(("+", second[j]))
                j += 1
            }
        }
        output.append(contentsOf: first[i...].map { ("-", $0) })
        output.append(contentsOf: second[j...].map { ("+", $0) })
        return output
    }
}
