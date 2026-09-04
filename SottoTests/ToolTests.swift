import Foundation
import os
import SwiftData
import Testing
@testable import Sotto

@MainActor
struct ArithmeticTests {
    @Test func evaluatesPrecedenceAndParentheses() throws {
        #expect(try Arithmetic.evaluate("17*23") == 391)
        #expect(try Arithmetic.evaluate("2+3*4") == 14)
        #expect(try Arithmetic.evaluate("(4.5+2)/3") == 6.5 / 3)
        #expect(try Arithmetic.evaluate("-7 + 2") == -5)
        #expect(try Arithmetic.evaluate("2^10") == 1024)
        #expect(try Arithmetic.evaluate("7/2") == 3.5)
        #expect(try Arithmetic.evaluate("10 % 3") == 1)
        #expect(try Arithmetic.evaluate("1,250 + 250") == 1500)
    }

    @Test func rejectsMalformedInputWithoutCrashing() {
        #expect(throws: Arithmetic.EvaluationError.self) { try Arithmetic.evaluate("2+") }
        #expect(throws: Arithmetic.EvaluationError.self) { try Arithmetic.evaluate("((2)") }
        #expect(throws: Arithmetic.EvaluationError.self) { try Arithmetic.evaluate("rm -rf /") }
        #expect(throws: Arithmetic.EvaluationError.self) { try Arithmetic.evaluate("1/0") }
        #expect(throws: Arithmetic.EvaluationError.self) { try Arithmetic.evaluate("") }
    }
}

@MainActor
struct BuiltInToolTests {
    @Test func calculatorFormatsResults() throws {
        #expect(try BuiltInTools.calculate("17*23") == "17*23 = 391")
        #expect(try BuiltInTools.calculate(" 7/2 ") == "7/2 = 3.5")
        #expect(throws: ToolExecutionError.self) { try BuiltInTools.calculate("2 +") }
    }

    @Test func convertsBetweenCompatibleUnits() throws {
        #expect(try BuiltInTools.convert(value: 5, from: "km", to: "mi").hasPrefix("5 km = 3.10"))
        #expect(try BuiltInTools.convert(value: 100, from: "c", to: "f").contains("212"))
        #expect(throws: ToolExecutionError.self) { try BuiltInTools.convert(value: 1, from: "kg", to: "km") }
        #expect(throws: ToolExecutionError.self) { try BuiltInTools.convert(value: 1, from: "widgets", to: "km") }
    }

    @Test func countsText() {
        let stats = BuiltInTools.textStatistics("Hello there. This is a test!")
        #expect(stats.contains("6 words"))
        #expect(stats.contains("2 sentences"))
    }

    /// A reading time is quoted only when there is enough text to have one. Reporting "about 1 min
    /// to read" for a single word was both wrong and the start of a chain: the model took the
    /// duration it had just been handed and called the unit converter on it.
    @Test func shortTextGetsNoReadingTime() {
        #expect(!BuiltInTools.textStatistics("hello").contains("min to read"))
        #expect(!BuiltInTools.textStatistics("Hello there. This is a test!").contains("min to read"))
        let long = String(repeating: "word ", count: 500)
        #expect(BuiltInTools.textStatistics(long).contains("2 min to read"))
    }

    @Test func datetimeMentionsTheTimeZone() {
        #expect(BuiltInTools.currentDateTime().contains(TimeZone.current.identifier))
    }
}

@MainActor
struct ToolCallParsingTests {
    @Test func parsesAWellFormedBlock() throws {
        let call = try #require(ToolCallParser.parse("<tool_call>\n{\"name\": \"calculate\", \"arguments\": {\"expression\": \"2+2\"}}\n</tool_call>"))
        #expect(call.name == "calculate")
        #expect(call.argumentsJSON == "{\"expression\":\"2+2\"}")
    }

    @Test func toleratesFencesAndParametersAlias() throws {
        let call = try #require(ToolCallParser.parse("```json\n{\"name\":\"x\",\"parameters\":{\"a\":1}}\n```"))
        #expect(call.name == "x")
        #expect(call.argumentsJSON == "{\"a\":1}")
    }

    @Test func recoversACallWhoseNameTheModelOmitted() throws {
        let tools = [
            ToolSpec(name: "calculate", description: "", parameters: [ToolParameter(name: "expression", type: .string, summary: "")]),
            ToolSpec(name: "convert_units", description: "", parameters: [
                ToolParameter(name: "value", type: .number, summary: ""),
                ToolParameter(name: "from", type: .string, summary: ""),
                ToolParameter(name: "to", type: .string, summary: ""),
            ]),
        ]
        let call = try #require(ToolCallParser.parse("{\"arguments\": {\"expression\": \"4321 * 8765\"}}", tools: tools))
        #expect(call.name == "calculate")
        #expect(call.argumentsJSON == "{\"expression\":\"4321 * 8765\"}")
    }

    @Test func doesNotGuessWhenSeveralToolsFit() {
        let tools = [
            ToolSpec(name: "a", description: "", parameters: [ToolParameter(name: "text", type: .string, summary: "")]),
            ToolSpec(name: "b", description: "", parameters: [ToolParameter(name: "text", type: .string, summary: "")]),
        ]
        #expect(ToolCallParser.parse("{\"arguments\": {\"text\": \"hi\"}}", tools: tools) == nil)
        #expect(ToolCallParser.parse("{\"arguments\": {\"text\": \"hi\"}}") == nil)
    }

    @Test func doesNotGuessWhenArgumentsDoNotFit() {
        let tools = [ToolSpec(name: "calculate", description: "", parameters: [ToolParameter(name: "expression", type: .string, summary: "")])]
        #expect(ToolCallParser.parse("{\"arguments\": {\"unknown\": 1}}", tools: tools) == nil)
    }

    @Test func rejectsNonsense() {
        #expect(ToolCallParser.parse("no json here") == nil)
        #expect(ToolCallParser.parse("{\"arguments\": {}}") == nil)
    }
}

@MainActor
struct ToolCallScannerTests {
    @Test func holdsBackPartialOpeningTag() {
        var scanner = ToolCallScanner()
        #expect(scanner.feed("Let me check. <tool").visible == "Let me check. ")
        let second = scanner.feed("_call>\n{\"name\":\"calculate\",\"arguments\":{\"expression\":\"1+1\"}}\n</tool_call>")
        #expect(second.visible.isEmpty)
        #expect(second.call?.name == "calculate")
    }

    @Test func passesPlainTextThrough() {
        var scanner = ToolCallScanner()
        #expect(scanner.feed("Hello, world.").visible == "Hello, world.")
        #expect(scanner.flush().visible.isEmpty)
    }

    @Test func keepsTextAfterABlock() {
        var scanner = ToolCallScanner()
        _ = scanner.feed("<tool_call>{\"name\":\"a\",\"arguments\":{}}</tool_call>")
        #expect(scanner.feed(" done").visible == " done")
    }

    @Test func reportsAnUnparsableBlock() {
        var scanner = ToolCallScanner()
        let output = scanner.feed("<tool_call>not json</tool_call>")
        #expect(output.call == nil)
        #expect(output.unparsedBlock != nil)
    }

    @Test func partialSuffixMatching() {
        #expect(ToolCallScanner.partialSuffixLength(of: "abc<tool", matching: "<tool_call>") == 5)
        #expect(ToolCallScanner.partialSuffixLength(of: "abc", matching: "<tool_call>") == 0)
    }

    @Test func recoversTheNamelessCallSeenFromQwen() {
        let tools = [ToolSpec(name: "calculate", description: "", parameters: [ToolParameter(name: "expression", type: .string, summary: "")])]
        var scanner = ToolCallScanner(tools: tools)
        // Exactly what the 3B model produced once its <tool_call> token had been stripped.
        let output = scanner.feed("{\"arguments\": {\"expression\": \"4321 * 8765\"}}")
        #expect(output.call?.name == "calculate")
        #expect(output.visible.isEmpty)
    }

    @Test func recognisesBareJSONWhenTagsAreStrippedBySpecialTokens() {
        var scanner = ToolCallScanner()
        // Qwen holds <tool_call> as a special token, so only the JSON reaches us.
        let output = scanner.feed("\n{\"name\": \"calculate\", \"arguments\": {\"expression\": \"4321 * 8765\"}}\n")
        #expect(output.call?.name == "calculate")
        #expect(output.visible.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test func bareJSONArrivingInPiecesIsHeldBack() {
        var scanner = ToolCallScanner()
        #expect(scanner.feed("{\"name\": \"calc").visible.isEmpty)
        #expect(scanner.feed("ulate\", \"arguments\": {\"expression\"").visible.isEmpty)
        let final = scanner.feed(": \"1+1\"}}")
        #expect(final.call?.name == "calculate")
        #expect(final.call?.argumentsJSON == "{\"expression\":\"1+1\"}")
    }

    @Test func jsonThatIsNotACallIsShownToTheUser() {
        var scanner = ToolCallScanner()
        let output = scanner.feed("{\"answer\": 42}")
        #expect(output.call == nil)
        #expect(output.visible == "{\"answer\": 42}")
    }

    @Test func bracesInsideStringsDoNotEndTheObject() {
        var scanner = ToolCallScanner()
        let output = scanner.feed("{\"name\":\"echo\",\"arguments\":{\"text\":\"a } b {\"}}")
        #expect(output.call?.name == "echo")
    }

    @Test func jsonLaterInAReplyStaysVisible() {
        var scanner = ToolCallScanner()
        #expect(scanner.feed("Here is an example: ").visible == "Here is an example: ")
        #expect(scanner.feed("{\"name\":\"x\",\"arguments\":{}}").visible.contains("{\"name\""))
    }

    @Test func unterminatedBlockStillParses() {
        var scanner = ToolCallScanner()
        _ = scanner.feed("<tool_call>{\"name\":\"a\",\"arguments\":{}}")
        #expect(scanner.flush().call?.name == "a")
    }
}

@MainActor
struct ToolPromptFormatterTests {
    @Test func describesEachTool() {
        let spec = ToolSpec(name: "calculate", description: "Does maths.", parameters: [ToolParameter(name: "expression", type: .string, summary: "The sum")])
        let text = ToolPromptFormatter.instructions(for: [spec])
        #expect(text.contains("calculate: Does maths."))
        #expect(text.contains("\"type\":\"string\""))
        #expect(text.contains("\"required\":[\"expression\"]"))
        #expect(ToolPromptFormatter.instructions(for: []).isEmpty)
    }

    @Test func tellsTheModelWhenToLeaveToolsAlone() {
        let spec = ToolSpec(name: "a", description: "b", parameters: [])
        let text = ToolPromptFormatter.instructions(for: [spec])
        #expect(text.contains(ToolPromptFormatter.usageRule))
        // The two traps a small model actually falls into, measured against the system model.
        #expect(ToolPromptFormatter.usageRule.contains("greeting is never a reason"))
        #expect(ToolPromptFormatter.usageRule.contains("in one word"))
    }

    @Test func appleInstructionsCarryTheSameRule() {
        let withTools = AppleIntelligenceEngine.instructionsText(
            systemPrompt: "Be brief.",
            toolRule: ToolPromptFormatter.usageRule
        )
        #expect(withTools.hasPrefix("Be brief."))
        #expect(withTools.contains("greeting is never a reason"))

        // Without tools the persona prompt is passed through untouched.
        #expect(AppleIntelligenceEngine.instructionsText(systemPrompt: "Be brief.", toolRule: nil) == "Be brief.")
        // With no persona the rule still reaches the model on its own.
        #expect(AppleIntelligenceEngine.instructionsText(systemPrompt: nil, toolRule: "rule") == "rule")
        #expect(AppleIntelligenceEngine.instructionsText(systemPrompt: "  ", toolRule: nil).isEmpty)
    }

    /// Every shipped description follows the same two-part shape: the requests that should reach
    /// the tool, then the near misses that should not. The negative half is the half that earns
    /// its tokens — a 3B model reaches for a tool it merely recognises, so the wording has to name
    /// the lure ("in one word" is not a request to count) rather than only the intended use.
    @Test func everyShippedToolSaysWhenNotToCallIt() {
        for tool in ToolDefinition.builtInSeeds() {
            #expect(tool.summary.contains("Use it when") || tool.summary.contains("Use it only when"),
                    "\(tool.name) does not say when to call it")
            #expect(tool.summary.contains("Do not call it") || tool.summary.contains("Never call it"),
                    "\(tool.name) does not say when to leave it alone")
            #expect(tool.seededSummary == tool.summary)
        }
    }

    @Test func keepsTheBasePrompt() {
        let spec = ToolSpec(name: "a", description: "b", parameters: [])
        let prompt = try! #require(ToolPromptFormatter.systemPrompt(base: "Be brief.", tools: [spec]))
        #expect(prompt.hasPrefix("Be brief."))
        #expect(prompt.contains("# Tools"))
        #expect(ToolPromptFormatter.systemPrompt(base: "Be brief.", tools: []) == "Be brief.")
    }
}

@MainActor
struct ToolTemplateTests {
    @Test func substitutesAndEscapes() {
        let url = ToolTemplate.substitute("https://x.test/?q={query}", arguments: ["query": "a b&c"]) { value in
            value.addingPercentEncoding(withAllowedCharacters: .sottoURLValueAllowed) ?? value
        }
        #expect(url == "https://x.test/?q=a%20b%26c")
    }

    @Test func quotesShellArguments() {
        let command = ToolTemplate.substitute("echo {text}", arguments: ["text": "hi; rm -rf /"]) { value in
            "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        #expect(command == "echo 'hi; rm -rf /'")
    }

    @Test func formatsNumbersWithoutDecimalNoise() {
        #expect(ToolTemplate.displayString(NSNumber(value: 5.0)) == "5")
        #expect(ToolTemplate.displayString(NSNumber(value: 2.5)) == "2.5")
        #expect(ToolTemplate.displayString(NSNumber(value: true)) == "true")
    }
}

@MainActor
struct HTTPToolTests {
    private let body = "{\"current\":{\"temperature\":21.5,\"list\":[{\"v\":\"first\"}]}}"

    @Test func followsADotPath() {
        #expect(HTTPTool.extract(path: "current.temperature", from: body) == "21.5")
        #expect(HTTPTool.extract(path: "current.list.0.v", from: body) == "first")
    }

    @Test func returnsTheWholeBodyWhenThePathMisses() {
        #expect(HTTPTool.extract(path: "", from: body) == body)
        #expect(HTTPTool.extract(path: "nope.here", from: body) == body)
    }
}

@MainActor
struct ToolDefinitionTests {
    @Test func validatesFunctionNames() {
        #expect(ToolDefinition.isValidName("weather_now"))
        #expect(!ToolDefinition.isValidName("Weather"))
        #expect(!ToolDefinition.isValidName("9lives"))
        #expect(!ToolDefinition.isValidName("a"))
        #expect(!ToolDefinition.isValidName("has space"))
    }

    @Test func suggestsNamesFromDisplayNames() {
        #expect(ToolDefinition.suggestedName(from: "Weather now") == "weather_now")
        #expect(ToolDefinition.suggestedName(from: "  3 Things!") == "things")
        #expect(ToolDefinition.suggestedName(from: "!") == "my_tool")
    }

    @Test func seededToolsAreWellFormedAndUnique() {
        let seeds = ToolDefinition.builtInSeeds()
        #expect(Set(seeds.map(\.name)).count == seeds.count)
        for seed in seeds {
            #expect(seed.isBuiltIn)
            #expect(ToolDefinition.isValidName(seed.name))
            #expect(!seed.summary.isEmpty)
        }
        // Everything that runs on device is ready to run; the one that reaches the network is not.
        let onDevice = seeds.filter { $0.kind == .builtIn }
        for seed in onDevice {
            #expect(!seed.usesNetwork)
            #expect(!seed.needsSetup)
        }
        // Four tools ship switched on. Text statistics is off because the system model reached
        // for it on prompts like "say hello in one word", which is noise rather than help; the
        // twenty tools added later are off because Apple's model takes every offered schema into
        // a 4,096-token window and fails outright once too many are there.
        let onByDefault = Set(onDevice.filter(\.isEnabled).map(\.name))
        #expect(onByDefault == ["current_datetime", "calculate", "convert_units", "search_conversations"])
        let networked = seeds.filter(\.usesNetwork)
        #expect(networked.count == 1)
        #expect(networked.allSatisfy { !$0.isEnabled && $0.approval == .askEveryTime })
    }

    @Test func schemaListsRequiredParametersOnly() {
        let spec = ToolSpec(name: "t", description: "d", parameters: [
            ToolParameter(name: "a", type: .string, summary: "A"),
            ToolParameter(name: "b", type: .number, summary: "B", isRequired: false),
        ])
        let json = spec.parametersSchemaJSON
        #expect(json.contains("\"required\":[\"a\"]"))
        #expect(json.contains("\"type\":\"number\""))
    }
}

@MainActor
struct PersonaToolSelectionTests {
    private func makeTools() -> [ToolDefinition] {
        let local = ToolDefinition(name: "local_tool", displayName: "Local", summary: "", kind: .builtIn, builtIn: .calculator)
        let remote = ToolDefinition(name: "remote_tool", displayName: "Remote", summary: "", kind: .httpRequest)
        return [local, remote]
    }

    @Test func modesFilterTheList() {
        let tools = makeTools()
        let persona = Persona(name: "P", summary: "", systemPrompt: "")
        #expect(persona.tools(from: tools).count == 2)
        persona.toolMode = .none
        #expect(persona.tools(from: tools).isEmpty)
        persona.toolMode = .selected
        persona.toolIDs = [tools[1].id]
        #expect(persona.tools(from: tools).map(\.name) == ["remote_tool"])
    }

    @Test func localOnlyPersonasNeverSeeNetworkTools() {
        let tools = makeTools()
        let persona = Persona(name: "P", summary: "", systemPrompt: "", localOnly: true)
        #expect(persona.tools(from: tools).map(\.name) == ["local_tool"])
        persona.toolMode = .selected
        persona.toolIDs = tools.map(\.id)
        #expect(persona.tools(from: tools).map(\.name) == ["local_tool"])
    }
}

@MainActor
struct ToolExecutorTests {
    @Test func requiredArgumentsAreChecked() {
        let parameters = [ToolParameter(name: "a", type: .string, summary: ""), ToolParameter(name: "n", type: .number, summary: "")]
        #expect(throws: ToolExecutionError.self) { try ToolExecutor.validate(["n": 1], against: parameters) }
        #expect(throws: ToolExecutionError.self) { try ToolExecutor.validate(["a": "x", "n": "not a number"], against: parameters) }
        #expect(throws: Never.self) { try ToolExecutor.validate(["a": "x", "n": 2], against: parameters) }
    }

    @Test func decodesArguments() {
        #expect(ToolExecutor.decodeArguments("{\"a\":1}").count == 1)
        #expect(ToolExecutor.decodeArguments("nonsense").isEmpty)
    }

    @Test func refusesInsecureURLs() async throws {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "SottoTests.\(UUID().uuidString)")!)
        var config = HTTPToolConfig()
        config.urlTemplate = "http://example.com"
        await #expect(throws: ToolExecutionError.insecureURL) {
            _ = try await HTTPTool.run(config, arguments: [:], settings: store)
        }
    }

    @Test func runsABuiltInToolEndToEnd() async throws {
        let container = try ModelContainer(
            for: PersistenceController.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let store = SettingsStore(defaults: UserDefaults(suiteName: "SottoTests.\(UUID().uuidString)")!)
        let executor = ToolExecutor(settings: store, context: container.mainContext)
        let tool = try #require(ToolDefinition.builtInSeeds().first { $0.builtIn == .calculator })
        let result = await executor.execute(tool, arguments: ["expression": "6*7"])
        #expect(result.success)
        #expect(result.text == "6*7 = 42")
        #expect(result.bytesSent == 0)

        let bad = await executor.execute(tool, arguments: [:])
        #expect(!bad.success)
        #expect(bad.text.hasPrefix("Error:"))
    }

    #if os(macOS) && SOTTO_SHELL_TOOL
    @Test func runsAShellToolWithQuotedArguments() async throws {
        var config = ShellToolConfig()
        config.command = "echo {text}"
        let output = try await ShellTool.run(config, arguments: ["text": "hello; echo pwned"])
        #expect(output.trimmingCharacters(in: .whitespacesAndNewlines) == "hello; echo pwned")
    }

    @Test func reportsAFailingCommand() async {
        var config = ShellToolConfig()
        config.command = "exit 3"
        await #expect(throws: ToolExecutionError.self) {
            _ = try await ShellTool.run(config, arguments: [:])
        }
    }
    #endif

    /// The shell tool is compiled out of App Store builds. Whichever build this is, the kind
    /// picker and the availability flag must agree, so a person is never offered a tool the
    /// executor will refuse.
    @Test func theShellKindIsOfferedOnlyWhenItIsCompiledIn() {
        #expect(ToolKind.creatableKinds.contains(.shellCommand) == ToolKind.shellToolIsCompiledIn)
        #expect(ToolKind.shellCommand.isAvailableOnThisPlatform == ToolKind.shellToolIsCompiledIn)
        #expect((ToolKind.shellCommand.unavailableReason == nil) == ToolKind.shellToolIsCompiledIn)
        // The other kinds are always offered.
        #expect(ToolKind.creatableKinds.contains(.webSearch))
        #expect(ToolKind.creatableKinds.contains(.httpRequest))
        #expect(!ToolKind.creatableKinds.contains(.builtIn))
    }

    /// A shell tool left in the database by a build that had the feature must not run in a
    /// build that does not — the executor refuses it rather than trusting the UI to hide it.
    @Test func aShellToolIsRefusedWhenTheFeatureIsNotCompiledIn() async throws {
        guard !ToolKind.shellToolIsCompiledIn else { return }
        let container = try ModelContainer(
            for: PersistenceController.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let store = SettingsStore(defaults: UserDefaults(suiteName: "SottoTests.\(UUID().uuidString)")!)
        let executor = ToolExecutor(settings: store, context: container.mainContext)
        let tool = ToolDefinition(name: "leftover", displayName: "Leftover", summary: "", kind: .shellCommand)
        tool.shellConfig = ShellToolConfig(command: "echo hi")
        let result = await executor.execute(tool, arguments: [:])
        #expect(!result.success)
        #expect(result.bytesSent == 0)
    }
}


/// Drives the approval and execution path that sits between a model's request and a tool run.
@MainActor
struct ChatSessionToolRunnerTests {
    /// Owns the container so it outlives the session that reads from its context.
    @MainActor
    private final class Harness {
        let services: AppServices
        let container: ModelContainer
        let session: ChatSession

        init(tools: [ToolDefinition], persona: Persona?) throws {
            services = AppServices()
            container = try ModelContainer(
                for: PersistenceController.schema,
                configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
            )
            let context = container.mainContext
            for tool in tools { context.insert(tool) }
            if let persona { context.insert(persona) }
            let conversation = Conversation(modelRef: .apple, personaID: persona?.id)
            context.insert(conversation)
            try context.save()
            session = ChatSession(conversation: conversation, services: services, context: context)
        }
    }

    private func calculatorTool() throws -> ToolDefinition {
        try #require(ToolDefinition.builtInSeeds().first { $0.builtIn == .calculator })
    }

    private func searchTool() throws -> ToolDefinition {
        try #require(ToolDefinition.builtInSeeds().first { $0.builtIn == .searchConversations })
    }

    private func waitForApproval(_ session: ChatSession) async throws {
        for _ in 0..<300 where session.pendingToolApproval == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func automaticToolRunsWithoutAsking() async throws {
        let calculator = try calculatorTool()
        let harness = try Harness(tools: [calculator], persona: nil)
        defer { withExtendedLifetime(harness) {} }
        let result = await harness.session.run(ToolCallRequest(name: "calculate", argumentsJSON: "{\"expression\":\"6*7\"}"))
        #expect(result.success)
        #expect(result.text == "6*7 = 42")
        #expect(harness.session.pendingToolApproval == nil)
        #expect(calculator.usageCount == 1)
    }

    @Test func askEveryTimeWaitsAndCanBeDeclined() async throws {
        let search = try searchTool()
        let harness = try Harness(tools: [search], persona: nil)
        defer { withExtendedLifetime(harness) {} }
        async let result = harness.session.run(ToolCallRequest(name: "search_conversations", argumentsJSON: "{\"query\":\"anything\"}"))
        try await waitForApproval(harness.session)
        #expect(harness.session.pendingToolApproval?.toolName == "search_conversations")
        harness.session.resolveToolApproval(.deny)
        let outcome = await result
        #expect(outcome.denied)
        #expect(!outcome.success)
        #expect(search.usageCount == 0)
        #expect(harness.session.pendingToolApproval == nil)
    }

    @Test func alwaysAllowFlipsTheToolToAutomatic() async throws {
        let search = try searchTool()
        let harness = try Harness(tools: [search], persona: nil)
        defer { withExtendedLifetime(harness) {} }
        async let result = harness.session.run(ToolCallRequest(name: "search_conversations", argumentsJSON: "{\"query\":\"zzz\"}"))
        try await waitForApproval(harness.session)
        harness.session.resolveToolApproval(.allowAlways)
        let outcome = await result
        #expect(outcome.success)
        #expect(search.approval == .automatic)
    }

    @Test func unknownToolsAreReportedToTheModel() async throws {
        let harness = try Harness(tools: [try calculatorTool()], persona: nil)
        defer { withExtendedLifetime(harness) {} }
        let result = await harness.session.run(ToolCallRequest(name: "does_not_exist", argumentsJSON: "{}"))
        #expect(!result.success)
        #expect(result.text.contains("does_not_exist"))
        #expect(result.text.contains("calculate"))
    }

    @Test func personaSelectionHidesToolsFromTheModel() async throws {
        let persona = Persona(name: "Terse", summary: "", systemPrompt: "")
        persona.toolMode = .none
        let harness = try Harness(tools: [try calculatorTool()], persona: persona)
        defer { withExtendedLifetime(harness) {} }
        #expect(harness.session.availableTools.isEmpty)
        let result = await harness.session.run(ToolCallRequest(name: "calculate", argumentsJSON: "{}"))
        #expect(!result.success)
    }

    @Test func theCallLimitStopsRunawayLoops() async throws {
        let harness = try Harness(tools: [try calculatorTool()], persona: nil)
        defer { withExtendedLifetime(harness) {} }
        for _ in 0..<ToolDefinition.maximumCallsPerTurn {
            let result = await harness.session.run(ToolCallRequest(name: "calculate", argumentsJSON: "{\"expression\":\"1+1\"}"))
            #expect(result.success)
        }
        let extra = await harness.session.run(ToolCallRequest(name: "calculate", argumentsJSON: "{\"expression\":\"1+1\"}"))
        #expect(!extra.success)
        #expect(extra.text.contains("tool calls"))
    }

    @Test func masterSwitchOffMeansNoTools() async throws {
        let harness = try Harness(tools: [try calculatorTool()], persona: nil)
        defer { withExtendedLifetime(harness) {} }
        harness.services.settings.toolsEnabled = false
        defer { harness.services.settings.toolsEnabled = true }
        #expect(harness.session.availableTools.isEmpty)
    }
}


@MainActor
struct WebSearchToolTests {
    private var config: WebSearchConfig {
        var config = WebSearchConfig()
        config.searchEngineID = "cx123"
        config.resultCount = 3
        return config
    }

    @Test func buildsTheRequestURL() throws {
        let url = try #require(WebSearchTool.makeURL(config, apiKey: "KEY", query: "swift concurrency"))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(url.host == "www.googleapis.com")
        #expect(values["key"] == "KEY")
        #expect(values["cx"] == "cx123")
        #expect(values["q"] == "swift concurrency")
        #expect(values["num"] == "3")
        #expect(values["safe"] == "active")
    }

    @Test func restrictsToASiteAndClampsTheCount() throws {
        var config = self.config
        config.site = "apple.com"
        config.resultCount = 50
        config.safeSearch = false
        let url = try #require(WebSearchTool.makeURL(config, apiKey: "K", query: "swiftdata"))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(values["q"] == "swiftdata site:apple.com")
        #expect(values["num"] == "10")
        #expect(values["safe"] == "off")
    }

    @Test func parsesAndFormatsResults() throws {
        let body = """
        {"items": [
          {"title": "Swift.org", "snippet": "The Swift programming language.", "link": "https://swift.org"},
          {"title": "Concurrency", "snippet": "Tasks and actors.", "link": "https://docs.swift.org/c"}
        ]}
        """
        let results = WebSearchTool.parse(Data(body.utf8), limit: 5)
        #expect(results.count == 2)
        #expect(results[0].title == "Swift.org")
        #expect(results[1].link == "https://docs.swift.org/c")

        let text = WebSearchTool.format(results, query: "swift")
        #expect(text.contains("1. Swift.org"))
        #expect(text.contains("2. Concurrency"))
        #expect(text.contains("https://swift.org"))
        #expect(text.contains("not verified facts"))
    }

    @Test func honoursTheResultLimitAndTruncatesLongSnippets() {
        let long = String(repeating: "a", count: 400)
        let body = "{\"items\": [{\"title\": \"T\", \"snippet\": \"\(long)\", \"link\": \"https://x.test\"}, {\"title\": \"U\", \"snippet\": \"s\", \"link\": \"https://y.test\"}]}"
        let results = WebSearchTool.parse(Data(body.utf8), limit: 1)
        #expect(results.count == 1)
        #expect(results[0].snippet.count <= WebSearchTool.snippetLimit + 1)
    }

    @Test func emptyAnswersParseToNothing() {
        #expect(WebSearchTool.parse(Data("{}".utf8), limit: 5).isEmpty)
        #expect(WebSearchTool.parse(Data("not json".utf8), limit: 5).isEmpty)
    }

    @Test func explainsGoogleFailures() {
        let body = Data("{\"error\": {\"message\": \"API key not valid\"}}".utf8)
        #expect(WebSearchTool.failureMessage(status: 403, body: body).contains("API key not valid"))
        #expect(WebSearchTool.failureMessage(status: 403, body: body).contains("Custom Search API"))
        #expect(WebSearchTool.failureMessage(status: 429, body: Data()).contains("100 searches a day"))
        #expect(WebSearchTool.failureMessage(status: 400, body: Data()).contains("search engine id"))
    }

    @Test func searchIsANetworkToolAndNeedsSetup() {
        let tool = try! #require(ToolDefinition.builtInSeeds().first { $0.kind == .webSearch })
        #expect(tool.usesNetwork)
        #expect(!tool.isEnabled)
        #expect(tool.needsSetup)
        #expect(!tool.isUsable)
        #expect(tool.name == "google_search")
        // A local-only persona must never be offered it.
        let persona = Persona(name: "Local", summary: "", systemPrompt: "", localOnly: true)
        #expect(persona.tools(from: [tool]).isEmpty)
    }
}

@MainActor
struct SeedRefreshTests {
    @Test func improvedWordingReplacesUntouchedDescriptions() throws {
        let container = try ModelContainer(
            for: PersistenceController.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let seed = try #require(ToolDefinition.builtInSeeds().first { $0.builtIn == .calculator })
        let stale = ToolDefinition(
            name: seed.name,
            displayName: seed.displayName,
            summary: "An older description.",
            kind: .builtIn,
            parameters: seed.parameters,
            approval: .automatic,
            isBuiltIn: true,
            builtIn: .calculator
        )
        stale.seededSummary = "An older description."
        let edited = try #require(ToolDefinition.builtInSeeds().first { $0.builtIn == .unitConverter })
        edited.summary = "My own wording."
        context.insert(stale)
        context.insert(edited)
        try context.save()

        PersistenceController.seedIfNeeded(context: context)

        #expect(stale.summary == seed.summary)
        #expect(stale.seededSummary == seed.summary)
        // A description the user rewrote is left exactly as they left it.
        #expect(edited.summary == "My own wording.")
        withExtendedLifetime(container) {}
    }
}

@MainActor
struct ToolCreationTests {
    @Test func newToolsGetAFreeFunctionName() {
        let first = ToolDefinition(name: "my_tool", displayName: "", summary: "", kind: .httpRequest)
        let second = ToolDefinition(name: "my_tool_2", displayName: "", summary: "", kind: .httpRequest)
        #expect(ToolsView.unusedName(among: []) == "my_tool")
        #expect(ToolsView.unusedName(among: [first]) == "my_tool_2")
        #expect(ToolsView.unusedName(among: [first, second]) == "my_tool_3")
    }

    @Test func setupIsRequiredUntilTheEssentialsAreThere() {
        let http = ToolDefinition(name: "h", displayName: "", summary: "", kind: .httpRequest)
        http.httpConfig = HTTPToolConfig()
        #expect(http.needsSetup)
        var config = HTTPToolConfig()
        config.urlTemplate = "https://example.com/{q}"
        http.httpConfig = config
        #expect(!http.needsSetup)

        let shell = ToolDefinition(name: "s", displayName: "", summary: "", kind: .shellCommand)
        shell.shellConfig = ShellToolConfig()
        #expect(shell.needsSetup)
        shell.shellConfig = ShellToolConfig(command: "date")
        #expect(!shell.needsSetup)
    }
}

@MainActor
struct KeychainStoreTests {
    @Test func storesAndRemovesASecret() throws {
        let account = "sotto.test.\(UUID().uuidString)"
        guard KeychainStore.set("hunter2", for: account) else {
            // Some CI keychains refuse writes; the app surfaces that to the user instead.
            Log.app.notice("Skipping keychain test: the keychain refused a write")
            return
        }
        defer { KeychainStore.remove(account) }
        #expect(KeychainStore.value(for: account) == "hunter2")
        #expect(KeychainStore.hasValue(for: account))
        #expect(KeychainStore.set("changed", for: account))
        #expect(KeychainStore.value(for: account) == "changed")
        #expect(KeychainStore.remove(account))
        #expect(KeychainStore.value(for: account) == nil)
        #expect(!KeychainStore.hasValue(for: account))
    }

    @Test func blankValuesRemoveRatherThanStore() {
        let account = "sotto.test.\(UUID().uuidString)"
        _ = KeychainStore.set("   ", for: account)
        #expect(KeychainStore.value(for: account) == nil)
    }
}

@Suite struct DynamicToolGatewayTests {
    private func spec(_ name: String, _ description: String = "does a thing", parameters: [ToolParameter] = []) -> ToolSpec {
        ToolSpec(name: name, description: description, parameters: parameters)
    }

    @Test func listsRequiredAndOptionalParametersInTheSignature() {
        let subject = spec("convert_units", "converts between units", parameters: [
            ToolParameter(name: "value", type: .number, summary: "the amount", isRequired: true),
            ToolParameter(name: "precision", type: .number, summary: "decimal places", isRequired: false),
        ])
        let line = DynamicToolGateway.line(for: subject)
        #expect(line == "convert_units(value, precision?) — converts between units")
    }

    @Test func catalogueNamesEveryToolAndCarriesTheRestraintRule() {
        let text = DynamicToolGateway.catalogue(for: [spec("current_datetime"), spec("calculate")])
        #expect(text.contains("current_datetime()"))
        #expect(text.contains("calculate()"))
        // Without the restraint rule the model treats the dispatcher as an invitation.
        #expect(text.contains(ToolPromptFormatter.usageRule))
    }

    @Test func catalogueSkipsToolsThatDoNotFitButKeepsLaterSmallOnes() {
        // A summary is capped, so the biggest a line gets is roughly thirty tokens.
        let wordy = spec("wordy", String(repeating: "long description ", count: 400))
        let small = spec("small", "tiny")
        // The preamble is charged to the same budget, so leave room for it plus a little.
        let budget = TokenEstimator.estimate(DynamicToolGateway.preamble) + 12
        let kept = DynamicToolGateway.fittingCatalogue([wordy, small], budget: budget)
        #expect(kept.map(\.name) == ["small"])
    }

    @Test func theShippedBuiltInLibraryFitsTheCatalogueBudget() {
        // The whole point of the gateway: every built-in is offered at once, which the
        // schema-per-tool path could not manage — it fits about twenty.
        let specs = ToolDefinition.builtInSeeds().map {
            ToolSpec(name: $0.name, description: $0.summary, parameters: $0.parameters)
        }
        #expect(specs.count > 20, "expected the built-in library to be larger than the old ceiling")
        #expect(DynamicToolGateway.fittingCatalogue(specs).count == specs.count)
    }

    @Test func summaryKeepsTheFirstSentenceAndDropsTheRest() {
        let full = "Returns the current date, time and time zone on this device. Use it when the user asks what the date is. Do not call it for a greeting."
        #expect(DynamicToolGateway.summary(of: full) == "Returns the current date, time and time zone on this device.")
    }

    @Test func summaryTruncatesAVeryLongFirstSentenceOnAWordBoundary() {
        let rambling = String(repeating: "word ", count: 60) + "end."
        let summary = DynamicToolGateway.summary(of: rambling)
        #expect(summary.count <= DynamicToolGateway.summaryCharacterLimit + 1)
        #expect(summary.hasSuffix("…"))
        #expect(!summary.contains("wor…"), "should cut between words, not inside one")
    }

    private var searchSpec: ToolSpec {
        spec("search_conversations", "Searches earlier chats.", parameters: [
            ToolParameter(name: "query", type: .string, summary: "Words to look for", isRequired: true),
        ])
    }

    @Test func readsArgumentsFromAJSONString() {
        #expect(DynamicToolGateway.argumentsJSON(from: "{\"query\": \"llm\"}", for: searchSpec) == "{\"query\":\"llm\"}")
    }

    @Test func readsArgumentsWrappedInACodeFence() {
        let fenced = "```json\n{\"query\": \"llm\"}\n```"
        #expect(DynamicToolGateway.argumentsJSON(from: fenced, for: searchSpec) == "{\"query\":\"llm\"}")
    }

    @Test func readsArgumentsSentAsAnObjectRatherThanAString() {
        #expect(DynamicToolGateway.argumentsJSON(from: ["query": "llm"], for: searchSpec) == "{\"query\":\"llm\"}")
    }

    @Test func acceptsABareValueForAToolWithOneRequiredTextParameter() {
        // The TestFlight failure: the model sent the search words with no JSON around them, the
        // argument was dropped, and the tool failed four times over.
        #expect(DynamicToolGateway.argumentsJSON(from: "llm", for: searchSpec) == "{\"query\":\"llm\"}")
    }

    @Test func doesNotGuessWhenAToolTakesSeveralRequiredParameters() {
        let convert = spec("convert_units", "Converts units.", parameters: [
            ToolParameter(name: "value", type: .number, summary: "amount", isRequired: true),
            ToolParameter(name: "from", type: .string, summary: "unit", isRequired: true),
        ])
        #expect(DynamicToolGateway.argumentsJSON(from: "5 km", for: convert) == "{}")
    }

    @Test func fallsBackToAnEmptyObjectRatherThanFailing() {
        #expect(DynamicToolGateway.argumentsJSON(from: nil, for: searchSpec) == "{}")
        #expect(DynamicToolGateway.argumentsJSON(from: "", for: searchSpec) == "{}")
        // Nothing to put a bare value into.
        let noParameters = spec("current_datetime", "The time now.")
        #expect(DynamicToolGateway.argumentsJSON(from: "today", for: noParameters) == "{}")
    }

    @Test func treatsAnythingUnparseableAsTheSingleParameterRatherThanLosingIt() {
        // Deliberate: for a one-parameter tool, passing the text through is always better than
        // dropping it, which is what produced the run of failed calls in the first place.
        #expect(DynamicToolGateway.argumentsJSON(from: "[1, 2]", for: searchSpec) == "{\"query\":\"[1, 2]\"}")
    }

    @Test func stopsCountingAfterRepeatedFailuresOfTheSameTool() {
        let ledger = ToolFailureLedger()
        #expect(ledger.failures(of: "search_conversations") == 0)
        ledger.recordFailure(of: "search_conversations")
        ledger.recordFailure(of: "search_conversations")
        #expect(ledger.failures(of: "search_conversations") >= DynamicToolGateway.repeatedFailureLimit)
        #expect(ledger.failures(of: "calculate") == 0)
    }

    @Test func catalogueTellsTheModelToAnswerGeneralKnowledgeItself() {
        let text = DynamicToolGateway.catalogue(for: [spec("search_conversations")])
        #expect(text.contains("Answer general-knowledge questions yourself"))
    }
}


@Suite struct ConversationMemoryTests {
    @Test func digestLeadsTheSystemPromptAndKeepsThePersona() {
        let prompt = ConversationMemory.systemPrompt(base: "You are terse.", digest: "User is called Yasas. Shipping an app.")
        let text = try! #require(prompt)
        #expect(text.contains("Earlier in this conversation"))
        #expect(text.contains("User is called Yasas"))
        #expect(text.contains("You are terse."))
        // The digest has to come first: it is context the instruction is read against.
        #expect(text.range(of: "User is called Yasas")!.lowerBound < text.range(of: "You are terse.")!.lowerBound)
    }

    @Test func anEmptyDigestLeavesThePersonaUntouched() {
        #expect(ConversationMemory.systemPrompt(base: "You are terse.", digest: "") == "You are terse.")
        #expect(ConversationMemory.systemPrompt(base: "You are terse.", digest: "   \n ") == "You are terse.")
        #expect(ConversationMemory.systemPrompt(base: nil, digest: "") == nil)
    }

    @Test func digestPromptCarriesTheEarlierSummaryAndTheNewTurns() {
        let turns = [
            ChatTurn(role: .user, content: "Call the project Sotto."),
            ChatTurn(role: .assistant, content: "Noted."),
        ]
        let prompt = ConversationMemory.digestPrompt(previous: "User prefers British spelling.", turns: turns)
        #expect(prompt.contains("User prefers British spelling."))
        #expect(prompt.contains("User: Call the project Sotto."))
        #expect(prompt.contains("Assistant: Noted."))
    }

    @Test func digestPromptOmitsTheSummarySectionOnTheFirstFold() {
        let prompt = ConversationMemory.digestPrompt(previous: "", turns: [ChatTurn(role: .user, content: "Hello")])
        #expect(!prompt.contains("Summary so far"))
    }

    @Test func stripsThePreambleASmallModelPutsInFront() {
        #expect(ConversationMemory.clean("Here is the summary: User is called Yasas.") == "User is called Yasas.")
        #expect(ConversationMemory.clean("```markdown\nUser ships apps.\n```") == "User ships apps.")
    }

    @Test func trimsAnOverlongDigestOnALineBoundary() {
        let long = (0..<200).map { "- note number \($0)" }.joined(separator: "\n")
        let cleaned = ConversationMemory.clean(long)
        #expect(cleaned.count <= ConversationMemory.maximumCharacters)
        #expect(!cleaned.hasSuffix("-"), "should not stop mid-note")
        #expect(cleaned.contains("note number 0"))
    }
}

@Suite struct SubagentTests {
    @Test func refusesAnEmptyTaskWithASentence() async {
        await #expect(throws: ToolExecutionError.self) {
            _ = try await Subagent.run(task: "   \n ", engine: CannedEngine())
        }
    }

    @Test func refusesATaskThatIsReallyTheWholeConversation() async {
        let huge = String(repeating: "context ", count: 400)
        #expect(huge.count > Subagent.maximumTaskCharacters)
        await #expect(throws: ToolExecutionError.self) {
            _ = try await Subagent.run(task: huge, engine: CannedEngine())
        }
    }

    @Test func returnsOnlyTheSubagentsAnswer() async throws {
        let answer = try await Subagent.run(task: "Say ready.", engine: CannedEngine())
        #expect(answer == "ready")
    }

    @Test func instructionsForbidTheThingsASubagentCannotDo() {
        // It has no one to ask and nowhere to report working-out, so the prompt has to say so.
        #expect(Subagent.instructions.contains("do not ask questions"))
        #expect(Subagent.instructions.contains("only its result"))
    }

    @Test func delegateShipsSwitchedOffAndAsksBeforeRunning() throws {
        let seed = try #require(ToolDefinition.builtInSeeds().first { $0.builtIn == .delegate })
        // It costs a whole extra generation, so it is never on by surprise.
        #expect(seed.isEnabled == false)
        #expect(seed.approval == .askEveryTime)
    }
}

@Suite struct ToolRelevanceTests {
    @Test func generalKnowledgeNeverReachesTheChatSearch() {
        // The exact message that reached for the chat search in builds 5 and 10.
        for question in [
            "What is a large language model?",
            "What is a LLM",
            "Explain how diffusion models work",
            "Who wrote Dune?",
        ] {
            #expect(!ToolRelevance.allows(.searchConversations, forUserMessage: question), "\(question) should not reach the chat search")
        }
    }

    @Test func aQuestionAboutTheirOwnPastStillReachesIt() {
        for question in [
            "What did I call that project last week?",
            "Remember the name we picked?",
            "What did you say about the icon earlier?",
            "Find my notes on pricing",
            "What did we discuss yesterday?",
        ] {
            #expect(ToolRelevance.allows(.searchConversations, forUserMessage: question), "\(question) should reach the chat search")
        }
    }

    @Test func matchesWholeWordsOnly() {
        // "week" must not match "we", "because" must not match "us".
        #expect(!ToolRelevance.referencesOwnHistory("How many days in a week"))
        #expect(!ToolRelevance.referencesOwnHistory("Explain because and therefore"))
        #expect(ToolRelevance.referencesOwnHistory("we agreed on green"))
    }

    @Test func everyOtherToolIsLeftToTheModel() {
        // "What is 17 * 23" is general knowledge in form and a fine reason to use arithmetic.
        #expect(ToolRelevance.allows(.calculator, forUserMessage: "What is 17 * 23?"))
        #expect(ToolRelevance.allows(.currentDateTime, forUserMessage: "What is the date?"))
        #expect(ToolRelevance.allows(.delegate, forUserMessage: "Summarise this passage"))
        #expect(ToolRelevance.allows(nil, forUserMessage: "anything"))
    }
}

extension ToolRelevanceTests {
    @Test func doesNotBlockWhenThereIsNoMessageToJudge() {
        // Running a tool outside a turn — the editor's "Run once" — has nothing to test against.
        #expect(ToolRelevance.allows(.searchConversations, forUserMessage: ""))
        #expect(ToolRelevance.allows(.searchConversations, forUserMessage: "   \n "))
    }
}
