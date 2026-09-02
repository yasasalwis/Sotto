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

    func generate(_ request: GenerationRequest) -> AsyncThrowingStream<GenerationEvent, Error> {
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

                    let messages = Self.llamaMessages(for: request)
                    let clock = ContinuousClock()
                    let start = clock.now
                    var finished = false
                    for try await event in model.generate(messages: messages, options: options) {
                        switch event {
                        case .promptProcessed(let count, _):
                            continuation.yield(.promptReady(tokens: count))
                        case .token(let text):
                            continuation.yield(.delta(text))
                        case .finished(let stats):
                            finished = true
                            runtime.record(stats: stats, contextLength: model.contextLength)
                            Self.updateMeasuredThroughput(record, sample: stats.tokensPerSecond)
                            let total = Self.seconds(start.duration(to: clock.now))
                            continuation.yield(.finished(GenerationOutcome(
                                promptTokens: stats.promptTokens,
                                generatedTokens: stats.generatedTokens,
                                promptSeconds: stats.promptSeconds,
                                generationSeconds: stats.generationSeconds,
                                totalSeconds: total,
                                tokensPerSecond: stats.tokensPerSecond > 0 ? stats.tokensPerSecond : nil,
                                finishReason: Self.map(stats.finishReason)
                            )))
                        }
                    }
                    if !finished {
                        continuation.yield(.finished(GenerationOutcome(promptTokens: nil, generatedTokens: nil, promptSeconds: nil, generationSeconds: 0, totalSeconds: Self.seconds(start.duration(to: clock.now)), tokensPerSecond: nil, finishReason: .cancelled)))
                    }
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

    static func llamaMessages(for request: GenerationRequest) -> [LlamaChatMessage] {
        var messages: [LlamaChatMessage] = []
        if let system = request.systemPrompt, !system.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
