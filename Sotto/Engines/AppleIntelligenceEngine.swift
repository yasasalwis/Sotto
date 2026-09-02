import Foundation
import FoundationModels
import os

/// Runs Apple's on-device foundation model through the FoundationModels framework.
final class AppleIntelligenceEngine: InferenceEngine {
    /// Apple's system model has a fixed 4,096-token window.
    static let fixedContextLength = 4096

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

    func generate(_ request: GenerationRequest) -> AsyncThrowingStream<GenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    if let reason = Self.unavailableReason {
                        throw EngineError.appleUnavailable(reason: reason)
                    }
                    guard let last = request.turns.last, last.role == .user else {
                        throw EngineError.noUserMessage
                    }
                    let transcript = Self.transcript(systemPrompt: request.systemPrompt, history: request.turns.dropLast())
                    let session = LanguageModelSession(model: .default, transcript: transcript)

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

    static func transcript(systemPrompt: String?, history: ArraySlice<ChatTurn>) -> Transcript {
        var entries: [Transcript.Entry] = []
        if let systemPrompt, !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            entries.append(.instructions(Transcript.Instructions(
                segments: [.text(Transcript.TextSegment(content: systemPrompt))],
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
