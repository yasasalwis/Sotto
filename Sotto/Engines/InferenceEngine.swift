import Foundation

struct ChatTurn: Hashable, Sendable {
    var role: MessageRole
    var content: String
}

struct GenerationRequest: Hashable, Sendable {
    var systemPrompt: String?
    var turns: [ChatTurn]
    var sampling: SamplingSettings
    var seed: UInt32?

    var lastUserTurn: ChatTurn? {
        turns.last(where: { $0.role == .user })
    }
}

enum FinishReason: String, Sendable, Hashable {
    case complete
    case maxTokens
    case contextFull
    case cancelled
}

struct GenerationOutcome: Hashable, Sendable {
    var promptTokens: Int?
    var generatedTokens: Int?
    var promptSeconds: Double?
    var generationSeconds: Double
    var totalSeconds: Double
    var tokensPerSecond: Double?
    var finishReason: FinishReason
}

enum GenerationEvent: Hashable, Sendable {
    /// The prompt has been ingested; `tokens` is exact for GGUF models and an estimate for Apple's model.
    case promptReady(tokens: Int?)
    case delta(String)
    /// The whole text so far should be replaced (used when a streamed snapshot is not a strict extension).
    case replace(String)
    case finished(GenerationOutcome)
}

enum EngineError: LocalizedError, Hashable {
    case appleUnavailable(reason: String)
    case guardrailViolation
    case contextWindowExceeded
    case rateLimited
    case concurrentRequests
    case unsupportedLanguage
    case refusal(String)
    case modelNotInstalled
    case modelFileMissing(String)
    case notEnoughMemory(needed: UInt64, available: UInt64)
    case promptTooLong(tokens: Int, limit: Int)
    case noUserMessage
    case busy
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .appleUnavailable(let reason):
            return reason
        case .guardrailViolation:
            return "Apple's on-device model declined this request under its safety rules. Try rephrasing, or use an imported model."
        case .contextWindowExceeded:
            return "This conversation is longer than the model's context window. Start a new chat or trim the attachment."
        case .rateLimited:
            return "The system model is busy. Wait a moment and try again."
        case .concurrentRequests:
            return "Another request to the system model is still running."
        case .unsupportedLanguage:
            return "The system model doesn't support this language yet. Try an imported model."
        case .refusal(let text):
            return text.isEmpty ? "The model declined to answer." : text
        case .modelNotInstalled:
            return "That model is no longer installed. Pick another one from the model menu."
        case .modelFileMissing(let name):
            return "The weights for “\(name)” are missing from disk. Re-import or re-download the model."
        case .notEnoughMemory(let needed, let available):
            return "Not enough memory to load this model: it needs about \(Format.bytes(needed)) and \(Format.bytes(available)) is available."
        case .promptTooLong(let tokens, let limit):
            return "Even the latest message alone is \(Format.integer(tokens)) tokens, more than the \(Format.integer(limit))-token context."
        case .noUserMessage:
            return "There's nothing to respond to yet."
        case .busy:
            return "A response is already being generated."
        case .underlying(let message):
            return message
        }
    }
}

protocol InferenceEngine {
    var displayName: String { get }
    var contextLength: Int { get }
    /// Whether `countTokens` is exact (GGUF tokenizer) or an estimate.
    var countsTokensExactly: Bool { get }
    func countTokens(_ text: String) async throws -> Int
    func generate(_ request: GenerationRequest) -> AsyncThrowingStream<GenerationEvent, Error>
}
