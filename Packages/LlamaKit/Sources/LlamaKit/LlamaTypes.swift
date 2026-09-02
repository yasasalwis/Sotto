import Foundation

/// Static facts about a GGUF model file, read from its header without loading weights.
public struct LlamaModelInfo: Sendable, Hashable, Codable {
    public var name: String
    public var architecture: String
    public var quantization: String
    public var parameterLabel: String
    public var parameterCount: UInt64
    public var fileSizeBytes: UInt64
    public var trainingContextLength: Int
    public var blockCount: Int
    public var hasChatTemplate: Bool
    public var formatVersion: UInt32
    public var tensorCount: Int

    public init(
        name: String,
        architecture: String,
        quantization: String,
        parameterLabel: String,
        parameterCount: UInt64,
        fileSizeBytes: UInt64,
        trainingContextLength: Int,
        blockCount: Int,
        hasChatTemplate: Bool,
        formatVersion: UInt32,
        tensorCount: Int
    ) {
        self.name = name
        self.architecture = architecture
        self.quantization = quantization
        self.parameterLabel = parameterLabel
        self.parameterCount = parameterCount
        self.fileSizeBytes = fileSizeBytes
        self.trainingContextLength = trainingContextLength
        self.blockCount = blockCount
        self.hasChatTemplate = hasChatTemplate
        self.formatVersion = formatVersion
        self.tensorCount = tensorCount
    }
}

/// One turn of a chat, in the role vocabulary that chat templates understand
/// (`system`, `user`, `assistant`).
public struct LlamaChatMessage: Sendable, Hashable {
    public var role: String
    public var content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

/// How a model is loaded into memory.
public struct LlamaLoadOptions: Sendable, Hashable {
    /// Requested context window in tokens. Clamped to the model's training context.
    public var contextLength: Int = 4096
    /// Logical batch size used while ingesting the prompt.
    public var batchSize: Int = 512
    /// Number of layers to offload to the GPU. `-1` offloads every layer, `0` keeps the model on the CPU.
    public var gpuLayers: Int = -1
    /// Thread count for generation. `nil` picks the machine's performance-core count.
    public var threads: Int? = nil
    /// `nil` lets llama.cpp decide per model and backend.
    public var useFlashAttention: Bool? = nil

    public init() {}
}

/// Sampling parameters for a single generation.
public struct LlamaSamplingOptions: Sendable, Hashable {
    public var temperature: Double = 0.7
    public var topP: Double = 0.9
    public var topK: Int = 40
    public var minP: Double = 0.05
    public var repeatPenalty: Double = 1.1
    public var repeatLastN: Int = 64
    public var maxTokens: Int = 1024
    /// Fixed seed for reproducible sampling. `nil` draws a fresh random seed.
    public var seed: UInt32? = nil
    /// Render special tokens (such as a model's `<tool_call>` marker) as text instead of dropping
    /// them. End-of-generation tokens still stop the stream and are never emitted.
    public var rendersSpecialTokens: Bool = false

    public init() {}
}

public enum LlamaFinishReason: String, Sendable, Hashable, Codable {
    case endOfGeneration
    case maxTokens
    case contextFull
    case cancelled
}

public struct LlamaGenerationStats: Sendable, Hashable {
    public var promptTokens: Int
    public var generatedTokens: Int
    public var promptSeconds: Double
    public var generationSeconds: Double
    public var finishReason: LlamaFinishReason

    public var tokensPerSecond: Double {
        guard generationSeconds > 0 else { return 0 }
        return Double(generatedTokens) / generationSeconds
    }

    public init(promptTokens: Int, generatedTokens: Int, promptSeconds: Double, generationSeconds: Double, finishReason: LlamaFinishReason) {
        self.promptTokens = promptTokens
        self.generatedTokens = generatedTokens
        self.promptSeconds = promptSeconds
        self.generationSeconds = generationSeconds
        self.finishReason = finishReason
    }
}

public enum LlamaGenerationEvent: Sendable, Hashable {
    /// The whole prompt has been ingested and the first token is about to be sampled.
    case promptProcessed(tokenCount: Int, seconds: Double)
    /// A decoded piece of UTF-8 text. Pieces are complete scalars; partial sequences are buffered.
    case token(String)
    case finished(LlamaGenerationStats)
}

public enum LlamaError: Error, Sendable, Hashable, LocalizedError {
    case fileNotFound(String)
    case notAGGUFFile(String)
    case modelLoadFailed(String)
    case contextCreationFailed
    case tokenizationFailed
    case promptTooLong(tokens: Int, limit: Int)
    case decodeFailed(code: Int32)
    case chatTemplateFailed
    case modelUnloaded

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let name):
            return "The model file “\(name)” could not be found."
        case .notAGGUFFile(let name):
            return "“\(name)” is not a readable GGUF file."
        case .modelLoadFailed(let name):
            return "“\(name)” could not be loaded. It may be corrupted, unsupported, or too large for this device."
        case .contextCreationFailed:
            return "There was not enough memory to create an inference context."
        case .tokenizationFailed:
            return "The prompt could not be tokenized."
        case .promptTooLong(let tokens, let limit):
            return "The prompt is \(tokens) tokens, but the context window is \(limit)."
        case .decodeFailed(let code):
            return "The model failed while decoding (code \(code))."
        case .chatTemplateFailed:
            return "The model's chat template could not be applied."
        case .modelUnloaded:
            return "The model has been unloaded."
        }
    }
}
