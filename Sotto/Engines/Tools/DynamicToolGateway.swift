import Foundation
import FoundationModels

/// One tool that stands in for the whole library: the model asks for a tool by name, and this
/// runs it.
///
/// The alternative — handing every enabled tool to `LanguageModelSession` up front — writes each
/// one's full `GenerationSchema` into Apple's 4,096-token window before the conversation starts.
/// That is expensive, it caps the library at roughly twenty tools (see
/// `AppleIntelligenceEngine.toolDefinitionTokenBudget`), and it invites a 3B model to reach for a
/// schema simply because the schema is sitting in front of it. A TestFlight report showed exactly
/// that: "what is an LLM?" came back having called a chat search *and* a unit converter
/// (`from: years, to: days`), the second of which failed, so the answer opened with an apology.
///
/// Here the model sees one tool and a plain list of names. Using anything means naming it
/// deliberately and supplying its arguments — a far higher bar than picking from schemas already
/// in context — and one schema leaves the window to the conversation instead of the menu.
nonisolated struct DynamicToolGateway: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String

    static let toolName = "use_tool"

    /// The same quarter of the window the schema-per-tool path is allowed
    /// (`AppleIntelligenceEngine.toolDefinitionTokenBudget`) — spent on names, parameter lists and
    /// one sentence each instead of full `GenerationSchema`s. That is the whole trade: the same
    /// budget now holds the entire library rather than the twenty tools schemas managed.
    static let catalogueTokenBudget = AppleIntelligenceEngine.toolDefinitionTokenBudget

    /// Longest catalogue summary. Tool descriptions run to a few hundred characters because they
    /// also say when *not* to call the tool; that guidance is what `usageRule` covers here, so the
    /// line only needs to say what the tool is for.
    static let summaryCharacterLimit = 120

    let name = Self.toolName
    let description: String
    let parameters: GenerationSchema

    private let specs: [ToolSpec]
    private let runner: ToolRunner
    private let ledger = ToolFailureLedger()

    init(specs: [ToolSpec], runner: ToolRunner) throws {
        let listed = Self.fittingCatalogue(specs)
        self.specs = listed
        self.runner = runner
        self.description = Self.catalogue(for: listed)
        self.parameters = try Self.schema()
    }

    /// The tools whose catalogue lines fit the budget, in the order the person put them in.
    static func fittingCatalogue(_ specs: [ToolSpec], budget: Int = catalogueTokenBudget) -> [ToolSpec] {
        var kept: [ToolSpec] = []
        var used = 0
        for spec in specs {
            let cost = TokenEstimator.estimate(line(for: spec))
            guard used + cost <= budget else { continue }
            used += cost
            kept.append(spec)
        }
        return kept
    }

    static func line(for spec: ToolSpec) -> String {
        let signature = spec.parameters
            .map { $0.isRequired ? $0.name : "\($0.name)?" }
            .joined(separator: ", ")
        return "\(spec.name)(\(signature)) — \(summary(of: spec.description))"
    }

    /// The first sentence of a description, capped. Whole descriptions would not fit: the built-in
    /// library alone runs to a few thousand characters because each one argues its own case.
    static func summary(of description: String) -> String {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        var sentence = trimmed
        if let end = trimmed.firstIndex(where: { $0 == "." || $0 == "?" || $0 == "!" }) {
            sentence = String(trimmed[...end])
        }
        guard sentence.count > summaryCharacterLimit else { return sentence }
        let cut = sentence.prefix(summaryCharacterLimit)
        // Cut on a word boundary so the line does not end mid-word.
        if let space = cut.lastIndex(of: " ") {
            return String(cut[..<space]) + "…"
        }
        return String(cut) + "…"
    }

    static func catalogue(for specs: [ToolSpec]) -> String {
        var text = "Runs one of this device's tools and returns its result. "
        text += ToolPromptFormatter.usageRule
        text += "\n\nAnswer general-knowledge questions yourself. \"What is X\", \"explain Y\" and \"how does Z work\" are answered from what you already know and are never a reason to call a tool. Call one only when the user asks for something you cannot do by writing an answer: search their own past chats, compute a number exactly, convert units, or work on text they gave you.\n\nSet \"tool\" to exactly one name from the list below, and \"arguments\" to a JSON object of that tool's parameters — for example {\"expression\": \"12 * 7\"}. When a tool takes a single value you may pass that value on its own. Do not invent a tool that is not listed.\n\n"
        text += specs.map { line(for: $0) }.joined(separator: "\n")
        return text
    }

    static func schema() throws -> GenerationSchema {
        let root = DynamicGenerationSchema(
            name: toolName,
            description: "The tool to run and the arguments to run it with.",
            properties: [
                DynamicGenerationSchema.Property(
                    name: "tool",
                    description: "The exact name of the tool to run, copied from the list.",
                    schema: DynamicGenerationSchema(type: String.self),
                    isOptional: false
                ),
                DynamicGenerationSchema.Property(
                    name: "arguments",
                    description: "That tool's parameters as a JSON object. Omit when it takes none.",
                    schema: DynamicGenerationSchema(type: String.self),
                    isOptional: true
                ),
            ]
        )
        return try GenerationSchema(root: root, dependencies: [])
    }

    // MARK: - Calling

    func call(arguments: GeneratedContent) async throws -> String {
        let fields = AppleDynamicTool.dictionary(from: arguments)
        let requested = (fields["tool"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !requested.isEmpty else {
            return "No tool was named. Set \"tool\" to one of: \(availableNames)."
        }
        guard let spec = resolve(requested) else {
            // Naming the alternatives is what lets the model recover inside the same turn rather
            // than apologising to the user for a failure it could have fixed itself.
            return "There is no tool called \"\(requested)\". Available tools: \(availableNames)."
        }
        // A 3B model that gets an error back will cheerfully repeat the identical call until the
        // turn's budget is gone and then apologise. TestFlight reported exactly that: four failed
        // chat searches followed by "I apologize for the repeated errors". Two is enough to learn from.
        guard ledger.failures(of: spec.name) < Self.repeatedFailureLimit else {
            return "\(spec.name) has already failed \(Self.repeatedFailureLimit) times in this reply. Do not call it again. Answer the user directly with what you already know."
        }
        let json = Self.argumentsJSON(from: fields["arguments"], for: spec)
        let result = await runner.run(ToolCallRequest(name: spec.name, argumentsJSON: json))
        if !result.success { ledger.recordFailure(of: spec.name) }
        return result.text
    }

    static let repeatedFailureLimit = 2

    var availableNames: String {
        specs.map(\.name).joined(separator: ", ")
    }

    /// Exact name first, then case-insensitively: small models capitalise inconsistently, and
    /// refusing a call over a capital letter helps nobody.
    func resolve(_ requested: String) -> ToolSpec? {
        if let exact = specs.first(where: { $0.name == requested }) { return exact }
        return specs.first { $0.name.caseInsensitiveCompare(requested) == .orderedSame }
    }

    /// The model supplies arguments as a JSON string. It sometimes sends an object instead,
    /// sometimes wraps the JSON in a code fence, and — the case that cost four failed chat
    /// searches in TestFlight — sometimes sends the bare value with no JSON around it at all.
    /// A tool with a single required text parameter can take that bare value directly, which turns
    /// a guaranteed failure into the call the model plainly meant to make.
    static func argumentsJSON(from value: Any?, for spec: ToolSpec) -> String {
        if let object = parsedObject(from: value) {
            return AppleDynamicTool.json(from: object)
        }
        let raw = (value as? String).map(cleaned) ?? ""
        let required = spec.parameters.filter(\.isRequired)
        if !raw.isEmpty, required.count == 1, required[0].type == .string {
            return AppleDynamicTool.json(from: [required[0].name: raw])
        }
        return "{}"
    }

    static func cleaned(_ text: String) -> String {
        text.replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parsedObject(from value: Any?) -> [String: Any]? {
        if let object = value as? [String: Any] { return object }
        guard let text = value as? String else { return nil }
        let trimmed = cleaned(text)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

}


/// Counts, per reply, how often a tool has come back unsuccessful, so the gateway can stop a model
/// repeating a call that cannot work. One gateway is built per generation, so the tally is
/// naturally scoped to a single turn.
final class ToolFailureLedger: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    func recordFailure(of name: String) {
        lock.lock()
        defer { lock.unlock() }
        counts[name, default: 0] += 1
    }

    func failures(of name: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[name] ?? 0
    }
}
