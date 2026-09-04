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
        text += "\n\nSet \"tool\" to exactly one name from the list below, and \"arguments\" to a JSON object of that tool's parameters — for example {\"expression\": \"12 * 7\"}. Leave \"arguments\" out when the tool takes none. Do not invent a tool that is not listed.\n\n"
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
        let json = Self.argumentsJSON(from: fields["arguments"])
        let result = await runner.run(ToolCallRequest(name: spec.name, argumentsJSON: json))
        return result.text
    }

    var availableNames: String {
        specs.map(\.name).joined(separator: ", ")
    }

    /// Exact name first, then case-insensitively: small models capitalise inconsistently, and
    /// refusing a call over a capital letter helps nobody.
    func resolve(_ requested: String) -> ToolSpec? {
        if let exact = specs.first(where: { $0.name == requested }) { return exact }
        return specs.first { $0.name.caseInsensitiveCompare(requested) == .orderedSame }
    }

    /// The model supplies arguments as a JSON string. It sometimes sends an object instead, and
    /// sometimes wraps the JSON in a code fence; both are accepted rather than lost.
    static func argumentsJSON(from value: Any?) -> String {
        switch value {
        case let text as String:
            let cleaned = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return "{}" }
            guard let data = cleaned.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return "{}"
            }
            return AppleDynamicTool.json(from: object)
        case let object as [String: Any]:
            return AppleDynamicTool.json(from: object)
        default:
            return "{}"
        }
    }
}
