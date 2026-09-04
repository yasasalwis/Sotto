import Foundation
import SwiftData
import Testing
@testable import Sotto

/// Every built-in added after the original five. Each tool is checked for the answer it gives on
/// good arguments and for the sentence it produces on bad ones, because a model reads both.
@MainActor
struct DateToolTests {
    /// A fixed calendar so the assertions do not move with the device's zone or the wall clock.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private func date(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: iso)!
    }

    @Test func readsTheDateFormatsAModelWrites() throws {
        let now = date("2026-09-03 12:00")
        for text in ["2026-09-03", "2026/09/03", "3 September 2026", "September 3, 2026", "3 Sep 2026"] {
            let parsed = try #require(DateTools.parse(text, now: now, calendar: calendar), "could not read \(text)")
            #expect(DateTools.isoDay(parsed.date, calendar: calendar) == "2026-09-03")
            #expect(parsed.isDateOnly)
        }
        let withTime = try #require(DateTools.parse("2026-09-03T18:30:00", now: now, calendar: calendar))
        #expect(!withTime.isDateOnly)
        #expect(DateTools.parse("the day after the big meeting", now: now, calendar: calendar) == nil)
    }

    @Test func readsRelativeWords() throws {
        let now = date("2026-09-03 12:00")
        #expect(DateTools.isoDay(try #require(DateTools.parse("today", now: now, calendar: calendar)).date, calendar: calendar) == "2026-09-03")
        #expect(DateTools.isoDay(try #require(DateTools.parse("tomorrow", now: now, calendar: calendar)).date, calendar: calendar) == "2026-09-04")
        #expect(DateTools.isoDay(try #require(DateTools.parse("yesterday", now: now, calendar: calendar)).date, calendar: calendar) == "2026-09-02")
    }

    @Test func measuresTheGapBetweenTwoDates() throws {
        let text = try DateTools.difference(["from": "2026-09-03", "to": "2026-12-25"], calendar: calendar)
        #expect(text.contains("113 calendar days later"))
        #expect(text.contains("16 weeks and 1 day"))
        #expect(text.contains("3 months, 22 days"))
    }

    @Test func reportsAGapThatRunsBackwards() throws {
        let text = try DateTools.difference(["from": "2026-12-25", "to": "2026-09-03"], calendar: calendar)
        #expect(text.contains("113 calendar days earlier"))
    }

    @Test func refusesADateItCannotRead() {
        #expect(throws: ToolExecutionError.self) { try DateTools.difference(["from": "next Whitsun"], calendar: calendar) }
        #expect(throws: ToolExecutionError.self) { try DateTools.difference([:], calendar: calendar) }
    }

    @Test func shiftsADateByEveryUnit() throws {
        let cases: [(String, Double, String)] = [
            ("days", 10, "2026-09-13"), ("weeks", 2, "2026-09-17"),
            ("months", 3, "2026-12-03"), ("years", -1, "2025-09-03"),
        ]
        for (unit, amount, expected) in cases {
            let text = try DateTools.shift(["date": "2026-09-03", "amount": amount, "unit": unit], calendar: calendar)
            #expect(text.contains(expected), "\(amount) \(unit) gave \(text)")
        }
    }

    @Test func namesTheUnitsItAccepts() {
        #expect(throws: ToolExecutionError.self) {
            try DateTools.shift(["date": "2026-09-03", "amount": 1, "unit": "fortnights"], calendar: calendar)
        }
    }

    @Test func findsTimeZonesByCityAndIdentifier() throws {
        #expect(DateTools.zones(matching: "Asia/Tokyo").first?.identifier == "Asia/Tokyo")
        #expect(DateTools.zones(matching: "Tokyo").first?.identifier == "Asia/Tokyo")
        #expect(DateTools.zones(matching: "new york").first?.identifier == "America/New_York")
        #expect(DateTools.zones(matching: "Atlantis").isEmpty)
        let text = try DateTools.timeInZone(["zone": "Asia/Tokyo"], now: date("2026-09-03 12:00"))
        #expect(text.contains("Asia/Tokyo"))
        #expect(throws: ToolExecutionError.self) { try DateTools.timeInZone(["zone": "Atlantis"]) }
    }

    @Test func describesACalendarDate() throws {
        let text = try DateTools.facts(["date": "2026-09-03"], calendar: calendar)
        #expect(text.contains("Thursday"))
        #expect(text.contains("September 2026, 30 days, quarter 3"))
        #expect(text.contains("Day 246 of 365"))
        #expect(text.contains("ISO week 36"))
        #expect(text.contains("not a leap year"))
        #expect(try DateTools.facts(["date": "2024-02-29"], calendar: calendar).contains("is a leap year"))
    }
}

@MainActor
struct TextToolTests {
    @Test func transformsEveryStyle() throws {
        let expected: [String: String] = [
            "upper": "HELLO THERE WORLD", "lower": "hello there world",
            "title": "Hello There World", "snake": "hello_there_world",
            "kebab": "hello-there-world", "slug": "hello-there-world",
            "camel": "helloThereWorld", "pascal": "HelloThereWorld",
        ]
        for (style, result) in expected {
            #expect(TextTools.transform("hello there world", style: style) == result, "\(style) failed")
        }
        #expect(TextTools.transform("hello. and again", style: "sentence") == "Hello. And again")
        #expect(TextTools.transform("  padded  ", style: "trim") == "padded")
        #expect(TextTools.transform("abc", style: "reverse") == "cba")
        #expect(TextTools.transform("café", style: "strip_accents") == "cafe")
    }

    @Test func splitsWordsAtCaseBoundaries() {
        #expect(TextTools.words(in: "toolExecutorRuns") == ["tool", "Executor", "Runs"])
        #expect(TextTools.words(in: "a-b_c d") == ["a", "b", "c", "d"])
        #expect(TextTools.words(in: "") == [])
    }

    @Test func rejectsAStyleItDoesNotHave() {
        #expect(throws: ToolExecutionError.self) { try TextTools.transform(["text": "x", "style": "sarcastic"]) }
    }

    @Test func replacesLiterallyAndCounts() throws {
        let text = try TextTools.replace(["text": "one two one", "find": "one", "replace": "three"])
        #expect(text.hasPrefix("2 replacements:"))
        #expect(text.hasSuffix("three two three"))
        #expect(try TextTools.replace(["text": "abc", "find": "z", "replace": "y"]).contains("does not appear"))
        // A regular expression is treated as the literal characters it is made of, not as a pattern.
        #expect(try TextTools.replace(["text": "a.c", "find": ".", "replace": "-"]).hasSuffix("a-c"))
    }

    @Test func honoursCaseSensitivity() throws {
        #expect(try TextTools.replace(["text": "Cat cat", "find": "cat", "replace": "dog"]).hasSuffix("Cat dog"))
        #expect(try TextTools.replace(["text": "Cat cat", "find": "cat", "replace": "dog", "match_case": false]).hasSuffix("dog dog"))
        #expect(throws: ToolExecutionError.self) { try TextTools.replace(["text": "a", "find": "", "replace": "b"]) }
    }

    @Test func extractsEachKind() throws {
        let text = "Write to a@b.com or c@d.org, see https://example.com #swift @sotto 10.0.0.1 and 42.5"
        #expect(try TextTools.matches(of: "email", in: text) == ["a@b.com", "c@d.org"])
        #expect(try TextTools.matches(of: "hashtag", in: text) == ["#swift"])
        #expect(try TextTools.matches(of: "mention", in: text) == ["@sotto"])
        #expect(try TextTools.matches(of: "ip_address", in: text) == ["10.0.0.1"])
        #expect(try TextTools.matches(of: "number", in: text).contains("42.5"))
        #expect(try TextTools.matches(of: "url", in: text).contains { $0.contains("example.com") })
    }

    @Test func reportsWhenNothingMatches() throws {
        #expect(try TextTools.extract(["text": "nothing here", "kind": "email"]).contains("No email found"))
        #expect(throws: ToolExecutionError.self) { try TextTools.extract(["text": "x", "kind": "postcode"]) }
    }

    @Test func honoursTheMatchLimit() throws {
        let text = (1...40).map { "user\($0)@example.com" }.joined(separator: " ")
        let output = try TextTools.extract(["text": text, "kind": "email", "limit": 5])
        #expect(output.contains("40 email matches (first 5 shown)"))
        #expect(output.components(separatedBy: "\n- ").count == 6)
    }

    @Test func sortsAndDeduplicates() throws {
        let lines = "banana\napple\napple\ncherry"
        #expect(try TextTools.sortLines(["text": lines]).hasSuffix("apple\napple\nbanana\ncherry"))
        let unique = try TextTools.sortLines(["text": lines, "unique": true])
        #expect(unique.contains("after removing 1 duplicate"))
        #expect(unique.hasSuffix("apple\nbanana\ncherry"))
        #expect(try TextTools.sortLines(["text": lines, "order": "descending"]).hasSuffix("cherry\nbanana\napple\napple"))
        #expect(try TextTools.sortLines(["text": "bbb\na\ncc", "order": "longest"]).hasSuffix("bbb\ncc\na"))
    }

    @Test func sortsNumberedLinesTheWayAPersonWould() throws {
        let output = try TextTools.sortLines(["text": "item10\nitem2\nitem1"])
        #expect(output.hasSuffix("item1\nitem2\nitem10"))
    }

    @Test func countsWordFrequency() throws {
        let text = "the cat sat on the mat. The cat was happy. Happy cat."
        let output = try TextTools.wordFrequency(["text": text, "limit": 2])
        #expect(output.contains("- cat: 3"))
        #expect(!output.contains("- the:"), "common words should be dropped by default")
        #expect(try TextTools.wordFrequency(["text": text, "ignore_common": false]).contains("- the: 3"))
        #expect(try TextTools.wordFrequency(["text": "..."]).contains("No countable words"))
    }

    @Test func comparesTwoTextsLineByLine() throws {
        let output = try TextTools.compare(["first": "alpha\nbeta\ngamma", "second": "alpha\ndelta\ngamma"])
        #expect(output.contains("1 line only in the first text, 1 only in the second"))
        #expect(output.contains("- beta"))
        #expect(output.contains("+ delta"))
        #expect(try TextTools.compare(["first": "same", "second": "same"]).contains("identical"))
    }

    @Test func refusesADiffTooLargeToBeUseful() {
        let long = (0...TextTools.maximumDiffLines).map(String.init).joined(separator: "\n")
        #expect(throws: ToolExecutionError.self) { try TextTools.compare(["first": long, "second": "x"]) }
    }
}

@MainActor
struct DataToolTests {
    private let document = "{\"user\":{\"name\":\"Ada\",\"tags\":[\"one\",\"two\"]},\"count\":2}"

    @Test func formatsAndValidatesJSON() throws {
        let pretty = try DataTools.formatJSON(["json": document])
        #expect(pretty.hasPrefix("Valid JSON, pretty:"))
        #expect(pretty.contains("\n  \"count\" : 2"))
        #expect(try DataTools.formatJSON(["json": document, "style": "minified"]).contains("{\"count\":2,"))
    }

    @Test func explainsWhyJSONIsInvalid() {
        #expect(throws: ToolExecutionError.self) { try DataTools.formatJSON(["json": "{\"a\": }"]) }
        #expect(throws: ToolExecutionError.self) { try DataTools.formatJSON(["json": "   "]) }
    }

    @Test func readsAValueByDotPath() throws {
        #expect(try DataTools.queryJSON(["json": document, "path": "user.name"]).contains("\"Ada\""))
        #expect(try DataTools.queryJSON(["json": document, "path": "user.tags.1"]).contains("\"two\""))
        #expect(try DataTools.queryJSON(["json": document, "path": "count"]).contains("is 2"))
        #expect(try DataTools.queryJSON(["json": document, "path": "user.tags"]).contains("an array of 2 items"))
    }

    /// A miss must say so rather than quietly handing back the whole document, which a model
    /// would then answer from as though it had found the value.
    @Test func saysWhenAPathIsNotThere() throws {
        let output = try DataTools.queryJSON(["json": document, "path": "user.email"])
        #expect(output.contains("No value at “user.email”"))
        #expect(output.contains("“user” has no “email”"))
        #expect(try DataTools.queryJSON(["json": document, "path": "nope"]).contains("the top level has no “nope”"))
    }

    @Test func summarisesCSV() throws {
        let csv = "name,score,note\nAda,10,first\nGrace,20,\nAlan,30,third"
        let output = try DataTools.summariseCSV(["csv": csv])
        #expect(output.hasPrefix("3 data rows, 3 columns"))
        #expect(output.contains("- score: numeric — min 10, max 30, mean 20, sum 60"))
        #expect(output.contains("- name: text — 3 distinct values"))
        #expect(output.contains("- note: text, 1 blank — 2 distinct values"))
    }

    @Test func parsesQuotedCSVFields() {
        let rows = DataTools.parseCSV("a,\"b,c\",d\n1,\"say \"\"hi\"\"\",3", delimiter: ",")
        #expect(rows.count == 2)
        #expect(rows[0] == ["a", "b,c", "d"])
        #expect(rows[1] == ["1", "say \"hi\"", "3"])
    }

    @Test func treatsTheFirstRowAsDataWhenAsked() throws {
        let output = try DataTools.summariseCSV(["csv": "1,2\n3,4", "has_header": false])
        #expect(output.hasPrefix("2 data rows, 2 columns"))
        #expect(output.contains("column 1"))
    }

    @Test func describesAListOfNumbers() throws {
        let output = try DataTools.describeNumbers(["numbers": "2, 4, 4, 4, 5, 5, 7, 9"])
        #expect(output.hasPrefix("8 numbers"))
        #expect(output.contains("sum 40, mean 5, median 4.5"))
        #expect(output.contains("min 2, max 9, range 7"))
        #expect(output.contains("standard deviation 2.13809"))
        #expect(throws: ToolExecutionError.self) { try DataTools.describeNumbers(["numbers": "none at all"]) }
    }

    @Test func handlesASingleNumber() throws {
        let output = try DataTools.describeNumbers(["numbers": "7"])
        #expect(output.contains("sum 7, mean 7, median 7"))
        #expect(output.contains("standard deviation 0"))
    }

    @Test func worksOutEveryPercentageMode() throws {
        #expect(try DataTools.percentage(["mode": "percent_of", "value": 15, "other": 200]).hasSuffix("= 30"))
        #expect(try DataTools.percentage(["mode": "what_percent", "value": 30, "other": 200]).contains("is 15% of"))
        #expect(try DataTools.percentage(["mode": "change", "value": 200, "other": 250]).contains("25% increase"))
        #expect(try DataTools.percentage(["mode": "change", "value": 200, "other": 150]).contains("25% decrease"))
        #expect(try DataTools.percentage(["mode": "increase", "value": 200, "other": 10]).hasSuffix("= 220"))
        #expect(try DataTools.percentage(["mode": "decrease", "value": 200, "other": 10]).hasSuffix("= 180"))
    }

    @Test func refusesPercentagesThatDivideByZero() {
        #expect(throws: ToolExecutionError.self) { try DataTools.percentage(["mode": "what_percent", "value": 1, "other": 0]) }
        #expect(throws: ToolExecutionError.self) { try DataTools.percentage(["mode": "change", "value": 0, "other": 1]) }
        #expect(throws: ToolExecutionError.self) { try DataTools.percentage(["mode": "half_of", "value": 1, "other": 2]) }
    }

    @Test func convertsNumberBases() throws {
        #expect(try DataTools.convertBase(["value": "255", "from_base": 10, "to_base": 16]).contains("= FF in base 16"))
        #expect(try DataTools.convertBase(["value": "ff", "from_base": 16, "to_base": 10]).contains("= 255 in base 10"))
        #expect(try DataTools.convertBase(["value": "1010", "from_base": 2, "to_base": 10]).contains("= 10 in base 10"))
        #expect(try DataTools.convertBase(["value": "0xFF", "from_base": 16, "to_base": 2]).contains("11111111"))
        #expect(try DataTools.convertBase(["value": "-12", "from_base": 10, "to_base": 2]).contains("-1100"))
        #expect(throws: ToolExecutionError.self) { try DataTools.convertBase(["value": "9", "from_base": 2, "to_base": 10]) }
    }
}

@MainActor
struct EncodingToolTests {
    @Test func roundTripsEveryFormat() throws {
        for format in EncodingTools.formats {
            let encoded = try EncodingTools.encode("héllo world/+", as: format)
            #expect(try EncodingTools.decode(encoded, from: format) == "héllo world/+", "\(format) did not round-trip")
        }
        #expect(try EncodingTools.encode("hi", as: "base64") == "aGk=")
        #expect(try EncodingTools.encode("hi", as: "hex") == "6869")
    }

    @Test func reportsUndecodableInput() {
        #expect(throws: ToolExecutionError.self) { try EncodingTools.decode("6", from: "hex") }
        #expect(throws: ToolExecutionError.self) { try EncodingTools.decode("zz", from: "hex") }
        #expect(throws: ToolExecutionError.self) { try EncodingTools.decode("////", from: "base64") }
        #expect(throws: ToolExecutionError.self) { try EncodingTools.encode(["text": "x", "format": "rot13"]) }
    }

    @Test func hashesWithKnownDigests() throws {
        let empty = try EncodingTools.hash(["text": ""])
        #expect(empty.contains("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"))
        #expect(try EncodingTools.hash(["text": "abc", "algorithm": "sha512"]).contains("ddaf35a193617aba"))
        // Broken algorithms are not offered, so asking for one is an error rather than a weak hash.
        #expect(throws: ToolExecutionError.self) { try EncodingTools.hash(["text": "abc", "algorithm": "md5"]) }
    }

    @Test func staysInsideTheRequestedRange() throws {
        for _ in 0..<50 {
            let output = try EncodingTools.random(["minimum": 1, "maximum": 6])
            let value = try #require(Int(output.prefix(while: \.isNumber)))
            #expect((1...6).contains(value))
        }
        #expect(try EncodingTools.random(["minimum": 5, "maximum": 5]).hasPrefix("5 "))
    }

    @Test func returnsSeveralNumbersAndRefusesABackwardsRange() throws {
        let output = try EncodingTools.random(["minimum": 1, "maximum": 10, "count": 4])
        #expect(output.hasPrefix("4 random whole numbers from 1 to 10:"))
        #expect(output.components(separatedBy: ", ").count == 4)
        #expect(throws: ToolExecutionError.self) { try EncodingTools.random(["minimum": 10, "maximum": 1]) }
        // A count beyond the cap is clamped rather than refused.
        let many = try EncodingTools.random(["minimum": 1, "maximum": 2, "count": 500])
        #expect(many.hasPrefix("\(EncodingTools.maximumRandomCount) random"))
    }

    @Test func estimatesTokens() throws {
        let output = try EncodingTools.estimateTokens(["text": "The quick brown fox jumps over the lazy dog."])
        #expect(output.contains("about 11 tokens"))
        #expect(output.contains("44 characters, 9 words"))
        #expect(output.contains("estimate"))
    }
}

@MainActor
struct ToolArgumentsTests {
    @Test func namesTheArgumentThatIsMissing() throws {
        #expect(throws: ToolExecutionError.self) { try ToolArguments.text([:], "text") }
        #expect(throws: ToolExecutionError.self) { try ToolArguments.number(["n": "words"], "n") }
        #expect(try ToolArguments.text([:], "style", fallback: "pretty") == "pretty")
        #expect(try ToolArguments.text(["style": "  "], "style", fallback: "pretty") == "pretty")
    }

    @Test func refusesTextBeyondTheCap() {
        let huge = String(repeating: "a", count: ToolArguments.maximumTextCharacters + 1)
        #expect(throws: ToolExecutionError.self) { try ToolArguments.text(["text": huge], "text") }
    }

    @Test func clampsIntegersIntoRange() {
        #expect(ToolArguments.integer(["n": 500], "n", fallback: 10, in: 1...100) == 100)
        #expect(ToolArguments.integer(["n": -5], "n", fallback: 10, in: 1...100) == 1)
        #expect(ToolArguments.integer([:], "n", fallback: 10, in: 1...100) == 10)
        #expect(ToolArguments.integer(["n": "7"], "n", fallback: 10, in: 1...100) == 7)
    }

    @Test func readsTheWordsModelsUseForYesAndNo() {
        #expect(ToolArguments.flag(["b": "yes"], "b", fallback: false))
        #expect(ToolArguments.flag(["b": true], "b", fallback: false))
        #expect(!ToolArguments.flag(["b": "off"], "b", fallback: true))
        #expect(ToolArguments.flag(["b": "perhaps"], "b", fallback: true))
    }

    /// Models write "Title Case" and "title_case" for the same choice, so both must land.
    @Test func matchesChoicesLoosely() throws {
        #expect(try ToolArguments.choice(["k": "IP Address"], "k", from: TextTools.matchKinds) == "ip_address")
        #expect(try ToolArguments.choice(["k": "strip-accents"], "k", from: TextTools.styles) == "strip_accents")
        #expect(throws: ToolExecutionError.self) { try ToolArguments.choice([:], "k", from: ["a"]) }
    }
}

/// The library as a whole: everything declared must run, and everything that runs must be declared.
@MainActor
struct BuiltInToolLibraryTests {
    @Test func everyIdentifierIsSeededAndEveryParameterIsDocumented() throws {
        let seeds = ToolDefinition.builtInSeeds()
        let byID = Dictionary(uniqueKeysWithValues: seeds.compactMap { seed in seed.builtIn.map { ($0, seed) } })
        #expect(byID.count == BuiltInToolID.allCases.count)
        for id in BuiltInToolID.allCases {
            let seed = try #require(byID[id], "\(id.rawValue) has no seed")
            #expect(seed.name == id.rawValue)
            #expect(seed.parameters.count <= ToolDefinition.maximumParameters)
            #expect(seed.summary.count <= ToolDefinition.maximumSummaryLength)
            for parameter in seed.parameters {
                #expect(!parameter.summary.isEmpty, "\(id.rawValue).\(parameter.name) has no description")
                #expect(ToolDefinition.isValidName(parameter.name), "\(id.rawValue).\(parameter.name) is not a usable name")
            }
        }
    }

    /// Each tool is run through the executor with plausible arguments, the way a model would call
    /// it, so a wiring mistake in the dispatch switch cannot pass unnoticed.
    @Test func everyToolRunsThroughTheExecutor() async throws {
        let arguments: [BuiltInToolID: [String: Any]] = [
            .delegate: ["task": "Reply with the single word: ready."],
            .currentDateTime: [:],
            .calculator: ["expression": "2+2"],
            .unitConverter: ["value": 5, "from": "km", "to": "mi"],
            .textStatistics: ["text": "Two words."],
            .searchConversations: ["query": "anything"],
            .dateDifference: ["from": "2026-01-01", "to": "2026-02-01"],
            .dateShift: ["date": "2026-01-01", "amount": 5, "unit": "days"],
            .timeInZone: ["zone": "UTC"],
            .calendarFacts: ["date": "2026-01-01"],
            .transformText: ["text": "hello world", "style": "upper"],
            .replaceText: ["text": "a b", "find": "a", "replace": "c"],
            .extractMatches: ["text": "a@b.com", "kind": "email"],
            .sortLines: ["text": "b\na"],
            .wordFrequency: ["text": "cat cat dog"],
            .compareTexts: ["first": "a", "second": "b"],
            .formatJSON: ["json": "{\"a\":1}"],
            .queryJSON: ["json": "{\"a\":1}", "path": "a"],
            .summarizeCSV: ["csv": "a,b\n1,2"],
            .describeNumbers: ["numbers": "1 2 3"],
            .percentage: ["mode": "percent_of", "value": 10, "other": 50],
            .convertBase: ["value": "255", "from_base": 10, "to_base": 16],
            .encodeText: ["text": "hi", "format": "base64"],
            .hashText: ["text": "hi"],
            .randomNumber: ["minimum": 1, "maximum": 6],
            .estimateTokens: ["text": "hello"],
        ]
        let container = try ModelContainer(
            for: PersistenceController.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let store = SettingsStore(defaults: UserDefaults(suiteName: "SottoTests.\(UUID().uuidString)")!)
        let executor = ToolExecutor(settings: store, context: container.mainContext, subagentEngine: CannedEngine())
        let seeds = ToolDefinition.builtInSeeds()

        for id in BuiltInToolID.allCases {
            let tool = try #require(seeds.first { $0.builtIn == id })
            let given = try #require(arguments[id], "\(id.rawValue) has no sample arguments")
            let result = await executor.execute(tool, arguments: given)
            #expect(result.success, "\(id.rawValue) failed: \(result.text)")
            #expect(result.bytesSent == 0, "\(id.rawValue) put bytes on the network")
            #expect(!result.text.isEmpty)
        }
    }

    /// Called with nothing at all, a tool must fail with a sentence rather than trap.
    @Test func everyToolSurvivesEmptyArguments() async throws {
        let container = try ModelContainer(
            for: PersistenceController.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let store = SettingsStore(defaults: UserDefaults(suiteName: "SottoTests.\(UUID().uuidString)")!)
        let executor = ToolExecutor(settings: store, context: container.mainContext)
        for tool in ToolDefinition.builtInSeeds() where tool.kind == .builtIn {
            let result = await executor.execute(tool, arguments: [:])
            let requiresNothing = tool.parameters.allSatisfy { !$0.isRequired }
            #expect(result.success == requiresNothing, "\(tool.name) behaved unexpectedly: \(result.text)")
            #expect(!result.text.isEmpty)
        }
    }

    /// What a fresh install offers a model. Every tool added after the original five ships
    /// switched off, because turning them all on breaks Apple Intelligence outright — measured on
    /// iOS 26.5, where twenty tools answered and twenty-four returned a bare `GenerationError`.
    /// The user turns on the ones they want, one switch at a time.
    @Test func onlyTheOriginalToolsShipSwitchedOn() {
        let enabled = Set(ToolDefinition.builtInSeeds().filter(\.isEnabled).map(\.name))
        #expect(enabled == ["current_datetime", "calculate", "convert_units", "search_conversations"])
        let tokens = TokenEstimator.estimate(ToolPromptFormatter.instructions(for: ToolDefinition.builtInSeeds().filter(\.isUsable).map(\.spec)))
        #expect(tokens <= 900, "the default tool prompt costs about \(tokens) tokens")
    }

    /// The counterpart to shipping them off: a user may switch every one of them on, and that must
    /// degrade rather than fail. The Apple engine drops what will not fit its window.
    @Test func theAppleEngineTrimsToolsToFitItsWindow() {
        let all = ToolDefinition.builtInSeeds().filter { $0.kind == .builtIn }.map(\.spec)
        #expect(all.count == BuiltInToolID.allCases.count)
        let offered = AppleIntelligenceEngine.toolsFittingBudget(all)
        #expect(offered.count < all.count, "the whole library is expected to overflow a 4,096-token window")
        #expect(!offered.isEmpty)

        // What survives keeps the user's order and fits the budget.
        #expect(offered.map(\.name) == all.map(\.name).filter { offered.map(\.name).contains($0) })
        let cost = offered.reduce(0) { $0 + TokenEstimator.estimate("\($1.name): \($1.description)\n\($1.parametersSchemaJSON)") }
        #expect(cost <= AppleIntelligenceEngine.toolDefinitionTokenBudget)

        // The budget sits well inside the twenty tools that answered on a real device.
        #expect(offered.count <= 20)
    }

    /// A short list is passed through untouched, so the budget never costs anything by default.
    @Test func theBudgetLeavesASmallListAlone() {
        let defaults = ToolDefinition.builtInSeeds().filter(\.isUsable).map(\.spec)
        #expect(AppleIntelligenceEngine.toolsFittingBudget(defaults).count == defaults.count)
        #expect(AppleIntelligenceEngine.toolsFittingBudget([]).isEmpty)
    }

    /// Every built-in runs on this device with no side effects, so none of them may reach the
    /// network or need setting up. Whether one ships switched on is a separate judgement about
    /// restraint, made per tool; what must hold is that the switch is the only thing in the way.
    @Test func theLibraryStaysLocalAndReady() {
        for tool in ToolDefinition.builtInSeeds() where tool.kind == .builtIn {
            #expect(!tool.usesNetwork, "\(tool.name) claims to use the network")
            #expect(!tool.hasSideEffects, "\(tool.name) claims to have side effects")
            #expect(!tool.needsSetup, "\(tool.name) needs setup")
            #expect(tool.isUsable == tool.isEnabled, "\(tool.name) is switched on but still unusable")
        }
    }
}


/// Stands in for a model so `delegate` can be exercised without Apple Intelligence or a GGUF file.
/// The library contract is that every declared tool runs; delegating needs an engine to run at all,
/// so the test supplies one rather than carving out an exception.
final class CannedEngine: InferenceEngine, @unchecked Sendable {
    let displayName = "Canned"
    let contextLength = 4096
    let countsTokensExactly = false

    func countTokens(_ text: String) async throws -> Int { TokenEstimator.estimate(text) }

    func generate(_ request: GenerationRequest, toolRunner: ToolRunner?) -> AsyncThrowingStream<GenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.delta("ready"))
            continuation.yield(.finished(GenerationOutcome(
                promptTokens: 1, generatedTokens: 1, promptSeconds: 0,
                generationSeconds: 0, totalSeconds: 0, tokensPerSecond: nil, finishReason: .complete
            )))
            continuation.finish()
        }
    }
}
