import Foundation
import SwiftData

enum ToolKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case builtIn
    case webSearch
    case httpRequest
    case shellCommand

    var id: String { rawValue }

    var label: String {
        switch self {
        case .builtIn: return "Built-in"
        case .webSearch: return "Google search"
        case .httpRequest: return "HTTPS request"
        case .shellCommand: return "Shell command"
        }
    }

    var explanation: String {
        switch self {
        case .builtIn: return "Runs inside Sotto, entirely on this device."
        case .webSearch: return "Searches Google with your own API key. The model's search words leave this device."
        case .httpRequest: return "Sends an HTTPS request. The arguments the model chooses leave this device."
        case .shellCommand: return "Runs a shell command as you, on this Mac. Only add commands you would run yourself."
        }
    }

    /// Whether the shell tool is built into this binary at all.
    ///
    /// It is compiled out of App Store builds: App Review guideline 2.5.2 does not allow an app
    /// to execute code that introduces or changes its functionality, and under App Sandbox the
    /// command is confined to Sotto's own container anyway, so it could not do the job it
    /// advertises. Builds distributed outside the store define `SOTTO_SHELL_TOOL` (see README).
    static let shellToolIsCompiledIn: Bool = {
        #if os(macOS) && SOTTO_SHELL_TOOL
        return true
        #else
        return false
        #endif
    }()

    var isAvailableOnThisPlatform: Bool {
        switch self {
        case .shellCommand: return Self.shellToolIsCompiledIn
        case .builtIn, .webSearch, .httpRequest: return true
        }
    }

    /// The kinds a person may pick when creating a tool. Built-ins ship with the app rather than
    /// being authored, and a kind this build cannot run is left out rather than shown greyed:
    /// offering a control that can never work is worse than not offering it.
    static var creatableKinds: [ToolKind] {
        allCases.filter { $0 != .builtIn && $0.isAvailableOnThisPlatform }
    }

    /// Why an existing tool of this kind cannot run here, for the badge on its row.
    var unavailableReason: String? {
        guard !isAvailableOnThisPlatform else { return nil }
        switch self {
        case .shellCommand:
            #if os(macOS)
            return "not in this build"
            #else
            return "macOS only"
            #endif
        case .builtIn, .webSearch, .httpRequest:
            return "unavailable"
        }
    }
}

enum ToolApprovalMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case askEveryTime
    case automatic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .askEveryTime: return "Ask every time"
        case .automatic: return "Run automatically"
        }
    }
}

enum ToolParameterType: String, Codable, CaseIterable, Identifiable, Sendable {
    case string
    case number
    case boolean

    var id: String { rawValue }

    var label: String {
        switch self {
        case .string: return "Text"
        case .number: return "Number"
        case .boolean: return "Yes / no"
        }
    }

    var jsonSchemaType: String {
        switch self {
        case .string: return "string"
        case .number: return "number"
        case .boolean: return "boolean"
        }
    }
}

struct ToolParameter: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var type: ToolParameterType
    var summary: String
    var isRequired: Bool

    init(id: UUID = UUID(), name: String, type: ToolParameterType = .string, summary: String = "", isRequired: Bool = true) {
        self.id = id
        self.name = name
        self.type = type
        self.summary = summary
        self.isRequired = isRequired
    }
}

/// Every tool that runs inside Sotto. The raw value is the function name the model calls, so it
/// is part of the app's contract with a conversation and must not change once shipped.
enum BuiltInToolID: String, Codable, CaseIterable, Identifiable, Sendable {
    // Original five.
    case currentDateTime = "current_datetime"
    case calculator = "calculate"
    case unitConverter = "convert_units"
    case textStatistics = "text_statistics"
    case searchConversations = "search_conversations"
    case delegate = "delegate"

    // Calendar.
    case dateDifference = "date_difference"
    case dateShift = "date_shift"
    case timeInZone = "time_in_zone"
    case calendarFacts = "calendar_facts"

    // Text.
    case transformText = "transform_text"
    case replaceText = "replace_text"
    case extractMatches = "extract_matches"
    case sortLines = "sort_lines"
    case wordFrequency = "word_frequency"
    case compareTexts = "compare_texts"

    // Data.
    case formatJSON = "format_json"
    case queryJSON = "query_json"
    case summarizeCSV = "summarize_csv"
    case describeNumbers = "describe_numbers"
    case percentage = "percentage"
    case convertBase = "convert_base"

    // Encoding and estimation.
    case encodeText = "encode_text"
    case hashText = "hash_text"
    case randomNumber = "random_number"
    case estimateTokens = "estimate_tokens"

    var id: String { rawValue }
}

/// Settings for the Google search tool. The API key is not here: it lives in the keychain,
/// looked up by the tool's id, so it never enters the database or an export.
nonisolated struct WebSearchConfig: Codable, Hashable, Sendable {
    /// The Programmable Search Engine id, shown as "cx" in Google's console.
    var searchEngineID: String = ""
    var resultCount: Int = 5
    var safeSearch: Bool = true
    /// Optional domain to restrict every search to, e.g. `apple.com`.
    var site: String = ""

    static let resultCountRange = 1...10
}

nonisolated struct HTTPToolConfig: Codable, Hashable, Sendable {
    var urlTemplate: String = "https://"
    var method: String = "GET"
    var headers: [String: String] = [:]
    var bodyTemplate: String = ""
    /// Dot path into the JSON response, e.g. `current.temperature`. Empty returns the whole body.
    var responsePath: String = ""
}

nonisolated struct ShellToolConfig: Codable, Hashable, Sendable {
    var command: String = ""
}

/// A tool the model may call. Built-ins ship with the app; other kinds are defined by the user.
@Model
final class ToolDefinition {
    @Attribute(.unique) var id: UUID
    /// Function name the model sees: lowercase letters, digits and underscores.
    var name: String
    var displayName: String
    /// What the model reads to decide when to call this tool.
    var summary: String
    var kindRaw: String
    var parametersData: Data
    var configData: Data?
    var approvalRaw: String
    var isEnabled: Bool
    var isBuiltIn: Bool
    var builtInRaw: String?
    var createdAt: Date
    var updatedAt: Date
    var usageCount: Int
    var sortOrder: Int
    /// The description this version of Sotto shipped. While `summary` still equals it, the app may
    /// replace both on upgrade; once the user edits the summary, their wording is left alone.
    var seededSummary: String?

    static let namePattern = "^[a-z][a-z0-9_]{1,40}$"
    static let maximumSummaryLength = 400
    static let maximumParameters = 8
    static let maximumResultCharacters = 4_000
    static let maximumCallsPerTurn = 4

    init(
        id: UUID = UUID(),
        name: String,
        displayName: String,
        summary: String,
        kind: ToolKind,
        parameters: [ToolParameter] = [],
        approval: ToolApprovalMode = .askEveryTime,
        isEnabled: Bool = true,
        isBuiltIn: Bool = false,
        builtIn: BuiltInToolID? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.summary = summary
        self.kindRaw = kind.rawValue
        self.parametersData = (try? JSONEncoder().encode(parameters)) ?? Data()
        self.approvalRaw = approval.rawValue
        self.isEnabled = isEnabled
        self.isBuiltIn = isBuiltIn
        self.builtInRaw = builtIn?.rawValue
        self.createdAt = .now
        self.updatedAt = .now
        self.usageCount = 0
        self.sortOrder = sortOrder
    }

    var kind: ToolKind {
        get { ToolKind(rawValue: kindRaw) ?? .builtIn }
        set { kindRaw = newValue.rawValue }
    }

    var approval: ToolApprovalMode {
        get { ToolApprovalMode(rawValue: approvalRaw) ?? .askEveryTime }
        set { approvalRaw = newValue.rawValue }
    }

    var builtIn: BuiltInToolID? { builtInRaw.flatMap(BuiltInToolID.init(rawValue:)) }

    var parameters: [ToolParameter] {
        get { (try? JSONDecoder().decode([ToolParameter].self, from: parametersData)) ?? [] }
        set { parametersData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var httpConfig: HTTPToolConfig? {
        get {
            guard let configData else { return nil }
            return try? JSONDecoder().decode(HTTPToolConfig.self, from: configData)
        }
        set { configData = try? JSONEncoder().encode(newValue) }
    }

    var webSearchConfig: WebSearchConfig? {
        get {
            guard let configData else { return nil }
            return try? JSONDecoder().decode(WebSearchConfig.self, from: configData)
        }
        set { configData = try? JSONEncoder().encode(newValue) }
    }

    /// Keychain account holding this tool's API key.
    var secretAccount: String { "tool.\(id.uuidString).apiKey" }

    var apiKey: String? { KeychainStore.value(for: secretAccount) }

    /// True when the tool cannot run until the user supplies something, such as an API key.
    var needsSetup: Bool {
        switch kind {
        case .webSearch:
            let hasEngine = !(webSearchConfig?.searchEngineID.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
            return !hasEngine || !KeychainStore.hasValue(for: secretAccount)
        case .httpRequest:
            return !(httpConfig?.urlTemplate.hasPrefix("https://") ?? false) || httpConfig?.urlTemplate == "https://"
        case .shellCommand:
            return shellConfig?.command.trimmingCharacters(in: .whitespaces).isEmpty ?? true
        case .builtIn:
            return false
        }
    }

    var shellConfig: ShellToolConfig? {
        get {
            guard let configData else { return nil }
            return try? JSONDecoder().decode(ShellToolConfig.self, from: configData)
        }
        set { configData = try? JSONEncoder().encode(newValue) }
    }

    /// True when running this tool can put bytes on the network.
    var usesNetwork: Bool { kind == .httpRequest || kind == .webSearch }

    /// True when the tool can change things outside Sotto.
    var hasSideEffects: Bool { kind == .shellCommand }

    var isUsable: Bool { isEnabled && kind.isAvailableOnThisPlatform && !needsSetup }

    var spec: ToolSpec { ToolSpec(name: name, description: summary, parameters: parameters) }

    static func isValidName(_ name: String) -> Bool {
        name.range(of: namePattern, options: .regularExpression) != nil
    }

    /// Turns a display name into a legal function name: "Weather now" → "weather_now".
    static func suggestedName(from displayName: String) -> String {
        var slug = displayName.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : "_"
        }
        while let first = slug.first, !first.isLetter {
            slug.removeFirst()
        }
        var name = String(slug.prefix(40))
        while name.contains("__") {
            name = name.replacingOccurrences(of: "__", with: "_")
        }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return name.count >= 2 ? name : "my_tool"
    }

    /// Built-in tools seeded on first launch, plus the Google search tool, which stays off until
    /// the user supplies credentials. Grouped so no one list grows past reading length; the order
    /// of the groups is the order they appear in the Tools list.
    static func builtInSeeds() -> [ToolDefinition] {
        let seeds = coreSeeds() + calendarSeeds() + textSeeds() + dataSeeds() + encodingSeeds()
        for seed in seeds {
            seed.seededSummary = seed.summary
        }
        return seeds
    }

    private static func coreSeeds() -> [ToolDefinition] {
        [
            ToolDefinition(
                name: BuiltInToolID.currentDateTime.rawValue,
                displayName: "Date & time",
                summary: "Returns the current date, time and time zone on this device. Use it when the user asks what the date or time is now, or when your answer cannot be correct without knowing today’s date, such as “how long until Friday”. Do not call it for a greeting, for a date the user already told you, or to add the date to an answer that did not ask for it.",
                kind: .builtIn,
                approval: .automatic,
                isBuiltIn: true,
                builtIn: .currentDateTime,
                sortOrder: 0
            ),
            ToolDefinition(
                name: BuiltInToolID.calculator.rawValue,
                displayName: "Calculator",
                summary: "Works out one arithmetic expression exactly, for example 17*23 or (4.5+2)/3. Use it when the user asks for a calculation, or your answer depends on one you have not been given. Do not call it to repeat a number the user supplied, to count words, letters or items, or for a sum you are only describing rather than performing.",
                kind: .builtIn,
                parameters: [ToolParameter(name: "expression", type: .string, summary: "Arithmetic using + - * / % ^ ( ) and decimal numbers")],
                approval: .automatic,
                isBuiltIn: true,
                builtIn: .calculator,
                sortOrder: 1
            ),
            ToolDefinition(
                name: BuiltInToolID.unitConverter.rawValue,
                displayName: "Unit converter",
                summary: "Converts a number from one unit of measure to another, for example 5 km to miles. Use it when the user gives a value and names both units. Do not call it when only one unit is named, when a measurement is mentioned in passing, or to convert something the user did not ask about.",
                kind: .builtIn,
                parameters: [
                    ToolParameter(name: "value", type: .number, summary: "The number to convert"),
                    ToolParameter(name: "from", type: .string, summary: "Source unit such as km, mi, kg, lb, c, f, l, gal, mph, gb"),
                    ToolParameter(name: "to", type: .string, summary: "Target unit"),
                ],
                approval: .automatic,
                isBuiltIn: true,
                builtIn: .unitConverter,
                sortOrder: 2
            ),
            ToolDefinition(
                name: BuiltInToolID.textStatistics.rawValue,
                displayName: "Text statistics",
                summary: "Counts the characters, words, sentences and reading time of a passage the user supplied. Use it only when the user asks how long their own text is, such as “how many words is this paragraph”. Never call it because of how the user asked you to answer: “in one word”, “briefly” and “in short” describe your reply, not text to measure. Never measure your own answer.",
                kind: .builtIn,
                parameters: [ToolParameter(name: "text", type: .string, summary: "The text to measure")],
                approval: .automatic,
                isEnabled: false,
                isBuiltIn: true,
                builtIn: .textStatistics,
                sortOrder: 3
            ),
            {
                let search = ToolDefinition(
                    name: "google_search",
                    displayName: "Google search",
                    summary: "Searches the web with Google and returns the top results as titles, snippets and links. Use it when the answer depends on information that changes, or the user asks you to look something up. Do not call it for greetings, opinions, arithmetic, or anything you already know.",
                    kind: .webSearch,
                    parameters: [
                        ToolParameter(name: "query", type: .string, summary: "What to search for, in a few words"),
                    ],
                    approval: .askEveryTime,
                    isEnabled: false,
                    isBuiltIn: true,
                    sortOrder: 5
                )
                search.webSearchConfig = WebSearchConfig()
                return search
            }(),
            ToolDefinition(
                name: BuiltInToolID.delegate.rawValue,
                displayName: "Delegate a task",
                summary: "Hands one self-contained task to a second model session and returns only its answer. Use it when a job needs a context window of its own, such as reading a long passage or working through several steps, so the working-out does not fill this chat. Do not call it for anything you can answer yourself, and never pass the user's question on unchanged. It cannot see this chat or ask you anything.",
                kind: .builtIn,
                parameters: [ToolParameter(name: "task", type: .string, summary: "The whole job, self-contained")],
                approval: .askEveryTime,
                isEnabled: false,
                isBuiltIn: true,
                builtIn: .delegate,
                sortOrder: 5
            ),
            ToolDefinition(
                name: BuiltInToolID.searchConversations.rawValue,
                displayName: "Search my chats",
                summary: "Searches the user’s earlier Sotto conversations for a phrase and returns matching snippets. Use it when the user refers to something from a previous chat, such as “what did I call that project last week”. Do not call it for the conversation in front of you, which you can already read, or for general knowledge. Everything stays on this device.",
                kind: .builtIn,
                parameters: [ToolParameter(name: "query", type: .string, summary: "Words to look for")],
                approval: .askEveryTime,
                isBuiltIn: true,
                builtIn: .searchConversations,
                sortOrder: 4
            ),
        ]
    }

    private static func calendarSeeds() -> [ToolDefinition] {
        [
            builtIn(.dateDifference, "Date difference", order: 6,
                summary: "Measures the gap between two dates in days, weeks, months and years. Use it when the user asks how long there is between two dates, or how far off one is. Do not call it for a duration the user already stated, or for a vague stretch of time such as “a while ago”.",
                parameters: [
                    ToolParameter(name: "from", type: .string, summary: "Start date as YYYY-MM-DD, or today, tomorrow, yesterday"),
                    ToolParameter(name: "to", type: .string, summary: "End date; the current moment when left out", isRequired: false),
                ]),
            builtIn(.dateShift, "Date shift", order: 7,
                summary: "Gives the date a number of days, weeks, months, years, hours or minutes before or after another date. Use it when the user asks what date something lands on, such as “90 days from today”. Do not call it when the user has already named the date, or to stamp an answer with a date nobody asked for.",
                parameters: [
                    ToolParameter(name: "amount", type: .number, summary: "How far to move; negative goes backwards"),
                    ToolParameter(name: "unit", type: .string, summary: "days, weeks, months, years, hours or minutes"),
                    ToolParameter(name: "date", type: .string, summary: "Starting date; today when left out", isRequired: false),
                ]),
            builtIn(.timeInZone, "Time elsewhere", order: 8,
                summary: "Reports the current date and time in another time zone and how far ahead or behind this device it is. Use it when the user asks what time it is somewhere else. Do not call it for the local time, for a place mentioned only in passing, or to restate a time the user already gave you.",
                parameters: [
                    ToolParameter(name: "zone", type: .string, summary: "A city or identifier such as Tokyo or Asia/Tokyo"),
                ]),
            builtIn(.calendarFacts, "Calendar facts", order: 9,
                summary: "Reports the weekday, month length, quarter, day of the year, ISO week number and leap year of one date. Use it when the user asks one of those about a particular date. Do not call it to decorate an answer with calendar trivia, or when a date is mentioned only in passing.",
                parameters: [
                    ToolParameter(name: "date", type: .string, summary: "The date to describe; today when left out", isRequired: false),
                ]),
        ]
    }

    private static func textSeeds() -> [ToolDefinition] {
        [
            builtIn(.transformText, "Transform text", order: 10,
                summary: "Rewrites text in one chosen style: upper, lower, title, sentence, snake, kebab, camel, pascal, slug, trim, reverse or strip_accents. Use it when the user asks for one of those exact changes. Do not call it for rewording, translating, summarising or correcting text — do that yourself.",
                parameters: [
                    ToolParameter(name: "text", type: .string, summary: "The text to rewrite"),
                    ToolParameter(name: "style", type: .string, summary: "One of the styles listed in the description"),
                ]),
            builtIn(.replaceText, "Find and replace", order: 11,
                summary: "Replaces every occurrence of one exact phrase with another and says how many changed. Use it when the user asks for a find and replace over text they supplied. Do not call it for a rewrite, an edit for tone, or a one-word change you can simply make yourself.",
                parameters: [
                    ToolParameter(name: "text", type: .string, summary: "The text to change"),
                    ToolParameter(name: "find", type: .string, summary: "The exact phrase to look for"),
                    ToolParameter(name: "replace", type: .string, summary: "What to put in its place; empty deletes it", isRequired: false),
                    ToolParameter(name: "match_case", type: .boolean, summary: "Match capitalisation exactly; true when left out", isRequired: false),
                ]),
            builtIn(.extractMatches, "Extract from text", order: 12,
                summary: "Pulls every email, url, number, hashtag, mention, ip_address, date or phone number out of a passage. Use it when the user asks you to collect one of those from text they supplied. Do not call it to find a single obvious value, and do not call it for topics, names or ideas: it matches patterns, not meaning.",
                parameters: [
                    ToolParameter(name: "text", type: .string, summary: "The text to search"),
                    ToolParameter(name: "kind", type: .string, summary: "email, url, number, hashtag, mention, ip_address, date or phone"),
                    ToolParameter(name: "limit", type: .number, summary: "How many to list, 1 to 100; 25 when left out", isRequired: false),
                ]),
            builtIn(.sortLines, "Sort lines", order: 13,
                summary: "Sorts the lines of a list ascending, descending, longest, shortest or reversed, and can drop repeats. Use it when the user asks for a list they supplied to be sorted or deduplicated. Do not call it to rank things by judgement or importance, or to tidy a list you wrote yourself.",
                parameters: [
                    ToolParameter(name: "text", type: .string, summary: "The lines to sort, one per line"),
                    ToolParameter(name: "order", type: .string, summary: "ascending, descending, longest, shortest or reverse", isRequired: false),
                    ToolParameter(name: "unique", type: .boolean, summary: "Remove repeated lines", isRequired: false),
                ]),
            builtIn(.wordFrequency, "Word frequency", order: 14,
                summary: "Counts which words appear most often in a piece of text. Use it when the user asks which words recur, or asks for a frequency count. Do not call it to summarise a text or find its themes, and never because the user asked for a short answer.",
                parameters: [
                    ToolParameter(name: "text", type: .string, summary: "The text to count"),
                    ToolParameter(name: "limit", type: .number, summary: "How many words to list, 1 to 50; 10 when left out", isRequired: false),
                    ToolParameter(name: "ignore_common", type: .boolean, summary: "Skip words like the and of; true when left out", isRequired: false),
                ]),
            builtIn(.compareTexts, "Compare texts", order: 15,
                summary: "Compares two texts line by line and lists the lines that differ. Use it when the user gives you two versions of something and asks what changed. Do not call it to weigh up two ideas, opinions or arguments — it compares literal text only.",
                parameters: [
                    ToolParameter(name: "first", type: .string, summary: "The original text"),
                    ToolParameter(name: "second", type: .string, summary: "The text to compare against it"),
                ]),
        ]
    }

    private static func dataSeeds() -> [ToolDefinition] {
        [
            builtIn(.formatJSON, "Format JSON", order: 16,
                summary: "Checks that JSON is valid and rewrites it pretty-printed or minified, naming the fault when it is not. Use it when the user asks you to format, tidy or check JSON. Do not call it to explain what the JSON means, and do not call it on text that is not JSON.",
                parameters: [
                    ToolParameter(name: "json", type: .string, summary: "The JSON text"),
                    ToolParameter(name: "style", type: .string, summary: "pretty or minified; pretty when left out", isRequired: false),
                ]),
            builtIn(.queryJSON, "Read from JSON", order: 17,
                summary: "Reads one value out of a JSON document by dot path, such as user.address.city or items.0.name. Use it when the user asks what a JSON document holds at a place. Do not call it for a value already plain to see in a short document, or to reshape or rewrite the JSON.",
                parameters: [
                    ToolParameter(name: "json", type: .string, summary: "The JSON text"),
                    ToolParameter(name: "path", type: .string, summary: "Dot path to the value; empty returns the whole document"),
                ]),
            builtIn(.summarizeCSV, "Summarise CSV", order: 18,
                summary: "Reports the rows, columns and per-column figures of CSV text. Use it when the user supplies CSV and asks what is in it. Do not call it on prose, on a handful of rows you can read directly, or to interpret what the data means.",
                parameters: [
                    ToolParameter(name: "csv", type: .string, summary: "The CSV text"),
                    ToolParameter(name: "delimiter", type: .string, summary: "Single character between fields; a comma when left out", isRequired: false),
                    ToolParameter(name: "has_header", type: .boolean, summary: "First row holds column names; true when left out", isRequired: false),
                ]),
            builtIn(.describeNumbers, "Describe numbers", order: 19,
                summary: "Gives the count, sum, mean, median, minimum, maximum, range and standard deviation of a list of numbers. Use it when the user asks for figures over numbers they supplied. Do not call it for a single number, for one simple sum — the calculator handles that — or for numbers you would have to invent.",
                parameters: [
                    ToolParameter(name: "numbers", type: .string, summary: "The numbers, separated by commas or spaces"),
                ]),
            builtIn(.percentage, "Percentages", order: 20,
                summary: "Works out percentages: percent_of, what_percent, change between two values, or increase and decrease by a percent. Use it when the user asks a percentage question. Do not call it to restate a percentage the user already gave, or to add one to an answer that did not ask for it.",
                parameters: [
                    ToolParameter(name: "mode", type: .string, summary: "percent_of, what_percent, change, increase or decrease"),
                    ToolParameter(name: "value", type: .number, summary: "The first number"),
                    ToolParameter(name: "other", type: .number, summary: "The second number, or the percentage for increase and decrease"),
                ]),
            builtIn(.convertBase, "Number bases", order: 21,
                summary: "Converts a whole number between bases 2 to 36, such as decimal to binary or hexadecimal. Use it when the user asks for a base conversion. Do not call it for a unit conversion, and do not call it for a number already written in the base asked for.",
                parameters: [
                    ToolParameter(name: "value", type: .string, summary: "The number, written in from_base"),
                    ToolParameter(name: "from_base", type: .number, summary: "Base it is written in, 2 to 36; 10 when left out", isRequired: false),
                    ToolParameter(name: "to_base", type: .number, summary: "Base to convert to, 2 to 36; 2 when left out", isRequired: false),
                ]),
        ]
    }

    private static func encodingSeeds() -> [ToolDefinition] {
        [
            builtIn(.encodeText, "Encode or decode", order: 22,
                summary: "Encodes or decodes text as base64, hex or url percent-encoding. Use it when the user names one of those three formats. Do not call it to encrypt, hash or hide anything: these encodings are reversible by anyone and are not security.",
                parameters: [
                    ToolParameter(name: "text", type: .string, summary: "The text to convert"),
                    ToolParameter(name: "format", type: .string, summary: "base64, hex or url"),
                    ToolParameter(name: "direction", type: .string, summary: "encode or decode; encode when left out", isRequired: false),
                ]),
            builtIn(.hashText, "Hash text", order: 23,
                summary: "Computes the SHA-256, SHA-384 or SHA-512 digest of text. Use it when the user asks for a hash or a checksum. Do not call it to encrypt anything, to store a password, or to encode text — encode_text does that.",
                parameters: [
                    ToolParameter(name: "text", type: .string, summary: "The text to hash"),
                    ToolParameter(name: "algorithm", type: .string, summary: "sha256, sha384 or sha512; sha256 when left out", isRequired: false),
                ]),
            builtIn(.randomNumber, "Random numbers", order: 24,
                summary: "Returns up to twenty random whole numbers in a range, for dice, picks and draws. Use it when the user asks for something random or asks you to choose. Never call it to invent a figure, a statistic or an example number for an answer.",
                parameters: [
                    ToolParameter(name: "minimum", type: .number, summary: "Lowest possible number; 1 when left out", isRequired: false),
                    ToolParameter(name: "maximum", type: .number, summary: "Highest possible number; 100 when left out", isRequired: false),
                    ToolParameter(name: "count", type: .number, summary: "How many numbers, 1 to 20; 1 when left out", isRequired: false),
                ]),
            builtIn(.estimateTokens, "Estimate tokens", order: 25,
                summary: "Estimates how many tokens a piece of text costs a model, alongside its characters and words. Use it when the user asks about token count or context budget. Do not call it to measure text for any other reason, and never because the user asked for a short answer.",
                parameters: [
                    ToolParameter(name: "text", type: .string, summary: "The text to measure"),
                ]),
        ]
    }

    /// Shorthand for the on-device built-ins added after the original five. They differ only in
    /// their wording and parameters: every one runs locally, has no side effects, and so runs
    /// without asking first.
    ///
    /// They ship switched **off**. Apple's system model reads every offered tool's schema into a
    /// 4,096-token window before the conversation starts, and past roughly twenty tools the
    /// session fails outright rather than answering worse — measured on iOS 26.5, where twenty
    /// tools answered and twenty-four returned a bare `GenerationError`. Turning them all on by
    /// default would have broken the app's own model on first launch, so the choice is the
    /// user's, one switch at a time, the same way `google_search` works.
    private static func builtIn(
        _ id: BuiltInToolID,
        _ displayName: String,
        order: Int,
        summary: String,
        parameters: [ToolParameter]
    ) -> ToolDefinition {
        ToolDefinition(
            name: id.rawValue,
            displayName: displayName,
            summary: summary,
            kind: .builtIn,
            parameters: parameters,
            approval: .automatic,
            isEnabled: false,
            isBuiltIn: true,
            builtIn: id,
            sortOrder: order
        )
    }
}
