import Foundation
import SwiftData

@Model
final class Persona {
    @Attribute(.unique) var id: UUID
    var name: String
    var summary: String
    var systemPrompt: String
    /// Preferred model. `nil` means "whatever the conversation uses".
    var modelRefRaw: String?
    var temperature: Double
    var topP: Double
    var maxTokens: Int
    var localOnly: Bool
    /// 1...9 binds ⌥⌘<slot>; `nil` means unbound.
    var shortcutSlot: Int?
    var isBuiltIn: Bool
    var createdAt: Date
    var updatedAt: Date
    var usageCount: Int
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        name: String,
        summary: String,
        systemPrompt: String,
        modelRef: ModelRef? = nil,
        temperature: Double = 0.7,
        topP: Double = 0.9,
        maxTokens: Int = 1024,
        localOnly: Bool = false,
        shortcutSlot: Int? = nil,
        isBuiltIn: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.systemPrompt = systemPrompt
        self.modelRefRaw = modelRef?.rawValue
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.localOnly = localOnly
        self.shortcutSlot = shortcutSlot
        self.isBuiltIn = isBuiltIn
        self.createdAt = .now
        self.updatedAt = .now
        self.usageCount = 0
        self.sortOrder = sortOrder
    }

    var modelRef: ModelRef? {
        get { modelRefRaw.flatMap(ModelRef.init(rawValue:)) }
        set { modelRefRaw = newValue?.rawValue }
    }

    static let maximumNameLength = 60
    static let maximumPromptLength = 8_000
    static let temperatureRange: ClosedRange<Double> = 0...2
    static let topPRange: ClosedRange<Double> = 0.05...1
    static let maxTokensRange: ClosedRange<Int> = 64...4096

    /// Built-in personas seeded on first launch. Prompts are Sotto's own.
    static func builtInSeeds() -> [Persona] {
        [
            Persona(
                name: "Editor",
                summary: "Cuts anything that doesn't carry meaning. Keeps your voice. Never adds “moreover.”",
                systemPrompt: "You are a line editor. Cut anything that doesn't carry meaning. Preserve the author's voice and vocabulary and do not smooth it into house style. Never add transitions such as “moreover” or “that said.” Return the edited text first, then at most two lines on what you removed and why.",
                temperature: 0.4,
                maxTokens: 1024,
                localOnly: true,
                shortcutSlot: 2,
                isBuiltIn: true,
                sortOrder: 0
            ),
            Persona(
                name: "Terse engineer",
                summary: "Answers in the fewest words that are still correct. Code first, prose after.",
                systemPrompt: "You are a senior engineer who answers in the fewest words that are still correct. Lead with code or the exact command when one exists, then at most three sentences of explanation. Never restate the question. If something is ambiguous, state the single assumption you made.",
                temperature: 0.2,
                maxTokens: 768,
                shortcutSlot: 1,
                isBuiltIn: true,
                sortOrder: 1
            ),
            Persona(
                name: "Explain like I'm curious",
                summary: "Analogies before definitions. Assumes algebra, not calculus.",
                systemPrompt: "Explain ideas to a curious adult who knows algebra but not calculus. Open with a concrete analogy, then the precise version, then one sentence on where the analogy breaks. Keep paragraphs short and avoid jargon unless you define it in the same sentence.",
                temperature: 0.7,
                maxTokens: 1024,
                shortcutSlot: 3,
                isBuiltIn: true,
                sortOrder: 2
            ),
            Persona(
                name: "Meeting notes",
                summary: "Decisions, owners, dates. Nothing else.",
                systemPrompt: "Turn raw notes into a structured record with exactly three headings: Decisions, Owners, Dates. Under each, use short bullet points. Do not add commentary, summaries, or anything not present in the notes. If a section is empty, write “none.”",
                temperature: 0.3,
                maxTokens: 768,
                localOnly: true,
                shortcutSlot: 4,
                isBuiltIn: true,
                sortOrder: 3
            ),
            Persona(
                name: "Shell helper",
                summary: "Explains commands, then gives the one you actually want.",
                systemPrompt: "You help with shell commands on macOS and Linux. When asked to explain a command, break it down flag by flag in a compact list. When asked for a command, give the safest version first, mark anything destructive, and prefer standard POSIX tools. Never run anything; only describe.",
                temperature: 0.1,
                maxTokens: 768,
                shortcutSlot: 5,
                isBuiltIn: true,
                sortOrder: 4
            ),
        ]
    }
}
