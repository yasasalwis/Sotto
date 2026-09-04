import Foundation

struct ChatTurn: Hashable, Sendable {
    var role: MessageRole
    var content: String
}

/// A tool as advertised to the model.
struct ToolSpec: Hashable, Sendable {
    var name: String
    var description: String
    var parameters: [ToolParameter]

    /// JSON-schema object describing the parameters, used by prompt-based tool calling.
    var parametersSchemaJSON: String {
        var properties: [String: Any] = [:]
        for parameter in parameters {
            properties[parameter.name] = [
                "type": parameter.type.jsonSchemaType,
                "description": parameter.summary,
            ]
        }
        let schema: [String: Any] = [
            "type": "object",
            "properties": properties,
            "required": parameters.filter(\.isRequired).map(\.name),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys]) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }
}

/// A call the model wants to make.
struct ToolCallRequest: Hashable, Sendable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var argumentsJSON: String
}

struct ToolRunResult: Hashable, Sendable {
    var text: String
    var success: Bool
    var denied: Bool
    var bytesSent: Int64
    var durationSeconds: Double

    static func denied(_ reason: String = "The user declined to run this tool. Continue without it.") -> ToolRunResult {
        ToolRunResult(text: reason, success: false, denied: true, bytesSent: 0, durationSeconds: 0)
    }
}

/// Executes tool calls for an engine. The chat session implements it so approval prompts and
/// result recording stay in one place.
protocol ToolRunner: AnyObject, Sendable {
    func run(_ call: ToolCallRequest) async -> ToolRunResult
}

struct GenerationRequest: Hashable, Sendable {
    var systemPrompt: String?
    var turns: [ChatTurn]
    var sampling: SamplingSettings
    var seed: UInt32?
    var tools: [ToolSpec] = []
    /// Offer the library through `DynamicToolGateway` rather than writing every schema into the
    /// context window. Only Apple's engine reads this; llama.cpp already lists tools in the prompt.
    var usesDynamicToolCalling: Bool = false

    var lastUserTurn: ChatTurn? {
        turns.last(where: { $0.role == .user })
    }
}

enum FinishReason: String, Sendable, Hashable {
    case toolLimit
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
    /// The model asked for a tool and the engine is waiting on the runner.
    case toolCall(ToolCallRequest)
    /// The runner answered; generation continues with the result in context.
    case toolResult(ToolCallRequest, ToolRunResult)
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
    case toolFailed(String)
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
        case .toolFailed(let message):
            return message
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
    func generate(_ request: GenerationRequest, toolRunner: ToolRunner?) -> AsyncThrowingStream<GenerationEvent, Error>
    /// Tokens this engine spends describing `tools` before the conversation begins.
    ///
    /// These are invisible to `PromptBuilder`, which trims history against `contextLength` alone.
    /// Left unaccounted, a full history plus the tool definitions can overrun the window and the
    /// turn fails outright — on Apple's engine with `exceededContextWindowSize`. Callers subtract
    /// this from the budget they hand the builder.
    func toolFootprintTokens(for tools: [ToolSpec], dynamic: Bool) -> Int
}

extension InferenceEngine {
    /// Engines that put nothing extra in the window.
    func toolFootprintTokens(for tools: [ToolSpec], dynamic: Bool) -> Int { 0 }

    /// Generation without tools, used by Compare and by any caller that doesn't run them.
    func generate(_ request: GenerationRequest) -> AsyncThrowingStream<GenerationEvent, Error> {
        generate(request, toolRunner: nil)
    }
}
