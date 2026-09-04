import Foundation
import FoundationModels
import os

/// Runs Apple's on-device foundation model through the FoundationModels framework.
final class AppleIntelligenceEngine: InferenceEngine {
    /// Apple's system model has a fixed 4,096-token window.
    static let fixedContextLength = 4096

    /// How much of that window the tool schemas may take.
    ///
    /// The framework writes every offered tool's description and parameter schema into the window
    /// before the conversation. Past a point the session does not answer worse — it fails, with a
    /// bare `GenerationError` that says nothing a user could act on.
    ///
    /// Measured on iOS 26.5 against the built-in library. Twenty tools answered and called the
    /// right one; twenty-four failed before running anything. At two fifths of the window the
    /// session got as far as four tool calls and then failed, because the schemas and the calls
    /// and their results all share the same 4,096 tokens — a turn may make up to
    /// `ToolDefinition.maximumCallsPerTurn` calls, and each result may be several hundred tokens.
    /// A quarter of the window leaves room for that whole exchange, and a smaller menu also makes
    /// a 3B model pick better.
    static let toolDefinitionTokenBudget = fixedContextLength / 4

    /// The tools that fit the budget, in the order the user put them in. A tool too large for the
    /// remaining room is skipped rather than ending the list, so a small tool further down still
    /// gets offered. Nothing is silently lost: the caller logs what was left out.
    static func toolsFittingBudget(_ specs: [ToolSpec], budget: Int = toolDefinitionTokenBudget) -> [ToolSpec] {
        var kept: [ToolSpec] = []
        var used = 0
        for spec in specs {
            let cost = TokenEstimator.estimate("\(spec.name): \(spec.description)\n\(spec.parametersSchemaJSON)")
            guard used + cost <= budget else { continue }
            used += cost
            kept.append(spec)
        }
        return kept
    }

    /// The tools handed to the session: one dispatcher when dynamic tool calling is on, otherwise
    /// as many full schemas as the window will take.
    static func tools(for request: GenerationRequest, runner: ToolRunner) -> [any Tool] {
        guard !request.tools.isEmpty else { return [] }
        if request.usesDynamicToolCalling {
            do {
                let gateway = try DynamicToolGateway(specs: request.tools, runner: runner)
                Log.engine.notice("Offering \(request.tools.count, privacy: .public) tools through one dispatcher")
                return [gateway]
            } catch {
                // A broken dispatcher must not cost the person their tools; fall through to the
                // schema-per-tool path, which is the behaviour every earlier build shipped.
                Log.engine.error("Dynamic tool gateway unavailable, offering schemas instead: \(error.localizedDescription, privacy: .public)")
            }
        }
        let offered = toolsFittingBudget(request.tools)
        if offered.count < request.tools.count {
            let dropped = Set(request.tools.map(\.name)).subtracting(offered.map(\.name)).sorted()
            Log.engine.notice("Offering \(offered.count, privacy: .public) of \(request.tools.count, privacy: .public) tools to Apple Intelligence; no room in the \(fixedContextLength, privacy: .public)-token window for: \(dropped.joined(separator: ", "), privacy: .public)")
        }
        return offered.compactMap { spec in
            do {
                return try AppleDynamicTool(spec: spec, runner: runner)
            } catch {
                Log.engine.error("Tool \(spec.name, privacy: .public) has an unusable schema: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    let displayName = "Apple Intelligence"
    var contextLength: Int { Self.fixedContextLength }
    let countsTokensExactly = false

    static var availability: SystemLanguageModel.Availability {
        SystemLanguageModel.default.availability
    }

    static var isAvailable: Bool {
        if case .available = availability { return true }
        return false
    }

    /// Short reason shown in pickers and onboarding when the model can't be used.
    static var unavailableReason: String? {
        switch availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "This device doesn't support Apple Intelligence."
            case .appleIntelligenceNotEnabled:
                return "Turn on Apple Intelligence in System Settings to use the on-device model."
            case .modelNotReady:
                return "Apple Intelligence is still downloading its model. Try again in a few minutes."
            @unknown default:
                return "Apple Intelligence isn't available right now."
            }
        }
    }

    static func prewarm() {
        guard isAvailable else { return }
        LanguageModelSession().prewarm()
    }

    func countTokens(_ text: String) async throws -> Int {
        TokenEstimator.estimate(text)
    }

    func generate(_ request: GenerationRequest, toolRunner: ToolRunner?) -> AsyncThrowingStream<GenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    if let reason = Self.unavailableReason {
                        throw EngineError.appleUnavailable(reason: reason)
                    }
                    guard let last = request.turns.last, last.role == .user else {
                        throw EngineError.noUserMessage
                    }
                    let transcript = Self.transcript(
                        systemPrompt: request.systemPrompt,
                        history: request.turns.dropLast(),
                        toolRule: request.tools.isEmpty ? nil : ToolPromptFormatter.usageRule
                    )
                    // The system model calls tools itself; the runner reports each call to the UI.
                    let tools: [any Tool] = toolRunner.map { runner in
                        Self.tools(for: request, runner: runner)
                    } ?? []
                    let session = LanguageModelSession(model: .default, tools: tools, transcript: transcript)

                    var options = GenerationOptions()
                    options.temperature = request.sampling.temperature
                    options.sampling = .random(probabilityThreshold: request.sampling.topP, seed: request.seed.map(UInt64.init))
                    options.maximumResponseTokens = request.sampling.maxTokens

                    let promptEstimate = TokenEstimator.estimate((request.systemPrompt ?? "") + request.turns.map(\.content).joined(separator: "\n"))
                    continuation.yield(.promptReady(tokens: promptEstimate))

                    let clock = ContinuousClock()
                    let start = clock.now
                    var firstToken: ContinuousClock.Instant?
                    var previous = ""
                    let stream = session.streamResponse(to: last.content, options: options)
                    for try await snapshot in stream {
                        try Task.checkCancellation()
                        let content = snapshot.content
                        if firstToken == nil { firstToken = clock.now }
                        if content.hasPrefix(previous) {
                            let delta = String(content.dropFirst(previous.count))
                            if !delta.isEmpty { continuation.yield(.delta(delta)) }
                        } else {
                            continuation.yield(.replace(content))
                        }
                        previous = content
                    }
                    let end = clock.now
                    let total = Self.seconds(start.duration(to: end))
                    let generationSeconds = firstToken.map { Self.seconds($0.duration(to: end)) } ?? total
                    let generated = TokenEstimator.estimate(previous)
                    continuation.yield(.finished(GenerationOutcome(
                        promptTokens: promptEstimate,
                        generatedTokens: generated,
                        promptSeconds: firstToken.map { Self.seconds(start.duration(to: $0)) },
                        generationSeconds: generationSeconds,
                        totalSeconds: total,
                        tokensPerSecond: generationSeconds > 0 ? Double(generated) / generationSeconds : nil,
                        finishReason: .complete
                    )))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.yield(.finished(GenerationOutcome(promptTokens: nil, generatedTokens: nil, promptSeconds: nil, generationSeconds: 0, totalSeconds: 0, tokensPerSecond: nil, finishReason: .cancelled)))
                    continuation.finish()
                } catch let error as LanguageModelSession.GenerationError {
                    Log.engine.error("Apple Intelligence generation failed: \(error.localizedDescription, privacy: .public)")
                    continuation.finish(throwing: Self.map(error))
                } catch let error as EngineError {
                    continuation.finish(throwing: error)
                } catch {
                    Log.engine.error("Apple Intelligence generation failed: \(error.localizedDescription, privacy: .public)")
                    continuation.finish(throwing: EngineError.underlying(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The persona's prompt plus, when tools are offered, the rule about leaving them alone.
    static func instructionsText(systemPrompt: String?, toolRule: String?) -> String {
        let base = systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return [base.isEmpty ? nil : base, toolRule]
            .compactMap { $0 }
            .joined(separator: "\n\n")
    }

    /// `toolRule` is added to the instructions when tools are offered; the framework supplies the
    /// schemas itself, but not the judgement about when to leave them alone.
    static func transcript(systemPrompt: String?, history: ArraySlice<ChatTurn>, toolRule: String? = nil) -> Transcript {
        var entries: [Transcript.Entry] = []
        let instructions = instructionsText(systemPrompt: systemPrompt, toolRule: toolRule)
        if !instructions.isEmpty {
            entries.append(.instructions(Transcript.Instructions(
                segments: [.text(Transcript.TextSegment(content: instructions))],
                toolDefinitions: []
            )))
        }
        var pendingPrompt: ChatTurn?
        for turn in history {
            switch turn.role {
            case .user:
                if let pending = pendingPrompt {
                    entries.append(.prompt(Transcript.Prompt(segments: [.text(Transcript.TextSegment(content: pending.content))])))
                    entries.append(.response(Transcript.Response(assetIDs: [], segments: [])))
                }
                pendingPrompt = turn
            case .assistant:
                if let pending = pendingPrompt {
                    entries.append(.prompt(Transcript.Prompt(segments: [.text(Transcript.TextSegment(content: pending.content))])))
                    pendingPrompt = nil
                    entries.append(.response(Transcript.Response(assetIDs: [], segments: [.text(Transcript.TextSegment(content: turn.content))])))
                }
            case .system:
                continue
            }
        }
        return Transcript(entries: entries)
    }

    private static func map(_ error: LanguageModelSession.GenerationError) -> EngineError {
        switch error {
        case .exceededContextWindowSize:
            return .contextWindowExceeded
        case .guardrailViolation:
            return .guardrailViolation
        case .rateLimited:
            return .rateLimited
        case .concurrentRequests:
            return .concurrentRequests
        case .unsupportedLanguageOrLocale:
            return .unsupportedLanguage
        case .assetsUnavailable:
            return .appleUnavailable(reason: "Apple Intelligence's model assets aren't available right now.")
        case .refusal:
            return .refusal(error.localizedDescription)
        default:
            return .underlying(error.localizedDescription)
        }
    }

    private static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
