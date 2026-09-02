import Foundation
import LlamaKit
import os

/// Inference engine backed by an installed GGUF model running through llama.cpp.
final class GGUFEngine: InferenceEngine {
    let record: InstalledModel
    let runtime: ModelRuntime

    init(record: InstalledModel, runtime: ModelRuntime) {
        self.record = record
        self.runtime = runtime
    }

    var displayName: String { record.name }
    let countsTokensExactly = true

    var contextLength: Int {
        if let model = runtime.loadedModel, runtime.loadedModelID == record.id {
            return model.contextLength
        }
        return min(runtime.settings.contextLength, max(record.contextLength, 512))
    }

    func countTokens(_ text: String) async throws -> Int {
        let model = try await runtime.model(for: record)
        return try await model.countTokens(in: text)
    }

    /// llama.cpp has no native tool protocol, so tools are offered in the system prompt and the
    /// reply is scanned for a `<tool_call>` block. When one appears the stream is stopped, the tool
    /// runs, its result is appended to the conversation, and generation restarts from there.
    func generate(_ request: GenerationRequest, toolRunner: ToolRunner?) -> AsyncThrowingStream<GenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    guard request.turns.last?.role == .user else { throw EngineError.noUserMessage }
                    let model = try await runtime.model(for: record)
                    runtime.beginGeneration()
                    defer { runtime.endGeneration() }

                    var options = LlamaSamplingOptions()
                    options.temperature = request.sampling.temperature
                    options.topP = request.sampling.topP
                    options.maxTokens = request.sampling.maxTokens
                    options.seed = request.seed

                    let toolsEnabled = toolRunner != nil && !request.tools.isEmpty
                    // Some vocabularies hold <tool_call> as a special token, which is dropped by
                    // default; render specials so the marker reaches the scanner.
                    options.rendersSpecialTokens = toolsEnabled
                    var messages = Self.llamaMessages(
                        for: request,
                        systemPrompt: toolsEnabled
                            ? ToolPromptFormatter.systemPrompt(base: request.systemPrompt, tools: request.tools)
                            : request.systemPrompt
                    )

                    let clock = ContinuousClock()
                    let start = clock.now
                    var promptTokens = 0
                    var generatedTokens = 0
                    var promptSeconds = 0.0
                    var generationSeconds = 0.0
                    var throughput: Double?
                    var reason = FinishReason.complete
                    var rounds = 0

                    rounds: while true {
                        var scanner = ToolCallScanner(tools: request.tools)
                        var pendingCall: ToolCallRequest?
                        var roundStats: LlamaGenerationStats?

                        for try await event in model.generate(messages: messages, options: options) {
                            switch event {
                            case .promptProcessed(let count, let seconds):
                                if rounds == 0 {
                                    promptTokens = count
                                    promptSeconds = seconds
                                    continuation.yield(.promptReady(tokens: count))
                                }
                            case .token(let text):
                                guard toolsEnabled else {
                                    continuation.yield(.delta(text))
                                    continue
                                }
                                let output = scanner.feed(text)
                                if !output.visible.isEmpty { continuation.yield(.delta(output.visible)) }
                                if let call = output.call {
                                    pendingCall = call
                                }
                                if let unparsed = output.unparsedBlock {
                                    // Not a usable call: show it rather than silently swallowing text.
                                    continuation.yield(.delta(unparsed))
                                }
                            case .finished(let stats):
                                roundStats = stats
                            }
                            if pendingCall != nil { break }
                        }

                        if toolsEnabled, pendingCall == nil {
                            let output = scanner.flush()
                            if !output.visible.isEmpty { continuation.yield(.delta(output.visible)) }
                            if let call = output.call { pendingCall = call }
                        }

                        if let stats = roundStats {
                            generatedTokens += stats.generatedTokens
                            generationSeconds += stats.generationSeconds
                            if stats.tokensPerSecond > 0 { throughput = stats.tokensPerSecond }
                            runtime.record(stats: stats, contextLength: model.contextLength)
                            Self.updateMeasuredThroughput(record, sample: stats.tokensPerSecond)
                            if pendingCall == nil {
                                reason = Self.map(stats.finishReason)
                                break rounds
                            }
                        } else if pendingCall == nil {
                            reason = .cancelled
                            break rounds
                        }

                        guard let call = pendingCall, let runner = toolRunner else {
                            break rounds
                        }
                        guard rounds < ToolDefinition.maximumCallsPerTurn else {
                            reason = .toolLimit
                            continuation.yield(.delta("\n\n_Stopped after \(ToolDefinition.maximumCallsPerTurn) tool calls._"))
                            break rounds
                        }
                        rounds += 1
                        continuation.yield(.toolCall(call))
                        let result = await runner.run(call)
                        continuation.yield(.toolResult(call, result))
                        messages.append(LlamaChatMessage(role: "assistant", content: ToolPromptFormatter.callBlock(call)))
                        messages.append(LlamaChatMessage(role: "user", content: ToolPromptFormatter.responseBlock(result)))
                        if Task.isCancelled {
                            reason = .cancelled
                            break rounds
                        }
                    }

                    continuation.yield(.finished(GenerationOutcome(
                        promptTokens: promptTokens,
                        generatedTokens: generatedTokens,
                        promptSeconds: promptSeconds,
                        generationSeconds: generationSeconds,
                        totalSeconds: Self.seconds(start.duration(to: clock.now)),
                        tokensPerSecond: throughput,
                        finishReason: reason
                    )))
                    continuation.finish()
                } catch let error as LlamaError {
                    Log.engine.error("GGUF generation failed: \(error.localizedDescription, privacy: .public)")
                    continuation.finish(throwing: Self.map(error))
                } catch let error as EngineError {
                    continuation.finish(throwing: error)
                } catch is CancellationError {
                    continuation.yield(.finished(GenerationOutcome(promptTokens: nil, generatedTokens: nil, promptSeconds: nil, generationSeconds: 0, totalSeconds: 0, tokensPerSecond: nil, finishReason: .cancelled)))
                    continuation.finish()
                } catch {
                    Log.engine.error("GGUF generation failed: \(error.localizedDescription, privacy: .public)")
                    continuation.finish(throwing: EngineError.underlying(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func llamaMessages(for request: GenerationRequest, systemPrompt: String? = nil) -> [LlamaChatMessage] {
        var messages: [LlamaChatMessage] = []
        let system = systemPrompt ?? request.systemPrompt
        if let system, !system.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(LlamaChatMessage(role: "system", content: system))
        }
        for turn in request.turns {
            messages.append(LlamaChatMessage(role: turn.role.rawValue, content: turn.content))
        }
        return messages
    }

    /// Exponential moving average so a single slow run doesn't swing the library's number.
    static func updateMeasuredThroughput(_ record: InstalledModel, sample: Double) {
        guard sample > 0 else { return }
        if let existing = record.measuredTokensPerSecond, existing > 0 {
            record.measuredTokensPerSecond = existing * 0.7 + sample * 0.3
        } else {
            record.measuredTokensPerSecond = sample
        }
        record.lastUsedAt = .now
    }

    private static func map(_ reason: LlamaFinishReason) -> FinishReason {
        switch reason {
        case .endOfGeneration: return .complete
        case .maxTokens: return .maxTokens
        case .contextFull: return .contextFull
        case .cancelled: return .cancelled
        }
    }

    private static func map(_ error: LlamaError) -> EngineError {
        switch error {
        case .promptTooLong(let tokens, let limit):
            return .promptTooLong(tokens: tokens, limit: limit)
        case .fileNotFound(let name):
            return .modelFileMissing(name)
        case .contextCreationFailed:
            return .notEnoughMemory(needed: 0, available: DeviceCapabilities.availableMemoryBytes())
        default:
            return .underlying(error.localizedDescription)
        }
    }

    private static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
