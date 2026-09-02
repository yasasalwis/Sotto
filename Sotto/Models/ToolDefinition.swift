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

enum BuiltInToolID: String, Codable, CaseIterable, Identifiable, Sendable {
    case currentDateTime = "current_datetime"
    case calculator = "calculate"
    case unitConverter = "convert_units"
    case textStatistics = "text_statistics"
    case searchConversations = "search_conversations"

    var id: String { rawValue }
}

/// Settings for the Google search tool. The API key is not here: it lives in the keychain,
/// looked up by the tool's id, so it never enters the database or an export.
struct WebSearchConfig: Codable, Hashable, Sendable {
    /// The Programmable Search Engine id, shown as "cx" in Google's console.
    var searchEngineID: String = ""
    var resultCount: Int = 5
    var safeSearch: Bool = true
    /// Optional domain to restrict every search to, e.g. `apple.com`.
    var site: String = ""

    static let resultCountRange = 1...10
}

struct HTTPToolConfig: Codable, Hashable, Sendable {
    var urlTemplate: String = "https://"
    var method: String = "GET"
    var headers: [String: String] = [:]
    var bodyTemplate: String = ""
    /// Dot path into the JSON response, e.g. `current.temperature`. Empty returns the whole body.
    var responsePath: String = ""
}

struct ShellToolConfig: Codable, Hashable, Sendable {
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
    /// the user supplies credentials.
    static func builtInSeeds() -> [ToolDefinition] {
        let seeds: [ToolDefinition] = [
            ToolDefinition(
                name: BuiltInToolID.currentDateTime.rawValue,
                displayName: "Date & time",
                summary: "Returns the current date, time and time zone on this device. Call it only when the answer depends on what the date or time is right now, such as “what day is it” or “how long until Friday”. Do not call it otherwise.",
                kind: .builtIn,
                approval: .automatic,
                isBuiltIn: true,
                builtIn: .currentDateTime,
                sortOrder: 0
            ),
            ToolDefinition(
                name: BuiltInToolID.calculator.rawValue,
                displayName: "Calculator",
                summary: "Works out an arithmetic expression exactly, for example 17*23 or (4.5+2)/3. Call it only when the user asks for a calculation, or your answer depends on one. Do not call it for numbers you are simply repeating.",
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
                summary: "Converts a number from one unit to another, for example 5 km to miles. Call it only when the user asks for a conversion and names both units. Never invent a conversion the user did not ask for.",
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
                summary: "Counts characters, words and sentences in text the user gave you, and estimates reading time. Call it only when the user asks how long a piece of text is. Do not call it on your own replies.",
                kind: .builtIn,
                parameters: [ToolParameter(name: "text", type: .string, summary: "The text to measure")],
                approval: .automatic,
                isBuiltIn: true,
                builtIn: .textStatistics,
                sortOrder: 3
            ),
            {
                let search = ToolDefinition(
                    name: "google_search",
                    displayName: "Google search",
                    summary: "Searches the web with Google and returns the top results as titles, snippets and links. Call it only when the answer depends on current information, or the user asks you to look something up. Do not call it for greetings, opinions, or things you already know.",
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
                name: BuiltInToolID.searchConversations.rawValue,
                displayName: "Search my chats",
                summary: "Searches the user's earlier Sotto conversations for a phrase and returns matching snippets. Call it only when the user refers to something said in an earlier chat. Everything stays on this device.",
                kind: .builtIn,
                parameters: [ToolParameter(name: "query", type: .string, summary: "Words to look for")],
                approval: .askEveryTime,
                isBuiltIn: true,
                builtIn: .searchConversations,
                sortOrder: 4
            ),
        ]
        for seed in seeds {
            seed.seededSummary = seed.summary
        }
        return seeds
    }
}
