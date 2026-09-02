import Foundation
import llama
import os
import Synchronization

private let modelLogger = Logger(subsystem: "lk.eonix.Sotto", category: "LlamaModel")
private let loaderQueue = DispatchQueue(label: "lk.eonix.Sotto.llama.loader", qos: .userInitiated)

/// Cooperative cancellation shared between Swift and the llama.cpp abort callback.
final class CancellationFlag: Sendable {
    private let storage = Atomic<Bool>(false)

    var isCancelled: Bool { storage.load(ordering: .relaxed) }

    func cancel() {
        storage.store(true, ordering: .relaxed)
    }
}

private final class ProgressBox: @unchecked Sendable {
    let handler: @Sendable (Double) -> Void

    init(_ handler: @escaping @Sendable (Double) -> Void) {
        self.handler = handler
    }
}

private let abortCallback: ggml_abort_callback = { data in
    guard let data else { return false }
    return Unmanaged<CancellationFlag>.fromOpaque(data).takeUnretainedValue().isCancelled
}

private let progressCallback: llama_progress_callback = { value, data in
    guard let data else { return true }
    Unmanaged<ProgressBox>.fromOpaque(data).takeUnretainedValue().handler(Double(value))
    return true
}

/// A loaded GGUF model plus one inference context. All llama.cpp calls are serialized on a
/// private queue so callers can use the async API from any actor.
public final class LlamaModel: @unchecked Sendable {
    public let url: URL
    public let info: LlamaModelInfo
    public let loadOptions: LlamaLoadOptions
    /// The context window actually allocated, after clamping to the model's training context.
    public let contextLength: Int
    public let threadCount: Int
    public let gpuLayers: Int

    private let queue = DispatchQueue(label: "lk.eonix.Sotto.llama.model", qos: .userInitiated)
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private let vocab: OpaquePointer
    private let batchSize: Int
    private let chatTemplate: String?
    private var activeGeneration: CancellationFlag?

    /// Loads a model on a background queue. `progress` receives values in 0...1 while tensors are mapped.
    public static func load(
        url: URL,
        options: LlamaLoadOptions = LlamaLoadOptions(),
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> LlamaModel {
        LlamaRuntime.initialize()
        let info = try GGUFMetadata.read(at: url)
        return try await withCheckedThrowingContinuation { continuation in
            loaderQueue.async {
                do {
                    continuation.resume(returning: try LlamaModel(url: url, info: info, options: options, progress: progress))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private init(url: URL, info: LlamaModelInfo, options: LlamaLoadOptions, progress: (@Sendable (Double) -> Void)?) throws {
        let path = url.path(percentEncoded: false)
        var modelParams = llama_model_default_params()
        #if targetEnvironment(simulator)
        let effectiveGPULayers = 0
        #else
        let effectiveGPULayers = options.gpuLayers < 0 ? 999 : options.gpuLayers
        #endif
        modelParams.n_gpu_layers = Int32(effectiveGPULayers)

        var progressBox: Unmanaged<ProgressBox>?
        if let progress {
            let box = Unmanaged.passRetained(ProgressBox(progress))
            progressBox = box
            modelParams.progress_callback = progressCallback
            modelParams.progress_callback_user_data = box.toOpaque()
        }
        defer { progressBox?.release() }

        guard let model = llama_model_load_from_file(path, modelParams) else {
            throw LlamaError.modelLoadFailed(url.lastPathComponent)
        }

        let trainingContext = Int(llama_model_n_ctx_train(model))
        let requested = max(512, options.contextLength)
        let effectiveContext = trainingContext > 0 ? min(requested, trainingContext) : requested
        let threads = options.threads ?? LlamaRuntime.recommendedThreadCount
        let batch = max(32, min(options.batchSize, effectiveContext))

        var contextParams = llama_context_default_params()
        contextParams.n_ctx = UInt32(effectiveContext)
        contextParams.n_batch = UInt32(batch)
        contextParams.n_ubatch = UInt32(batch)
        contextParams.n_threads = Int32(threads)
        contextParams.n_threads_batch = Int32(threads)
        contextParams.no_perf = true
        if let flash = options.useFlashAttention {
            contextParams.flash_attn_type = flash ? LLAMA_FLASH_ATTN_TYPE_ENABLED : LLAMA_FLASH_ATTN_TYPE_DISABLED
        }

        guard let context = llama_init_from_model(model, contextParams) else {
            llama_model_free(model)
            throw LlamaError.contextCreationFailed
        }

        self.url = url
        self.info = info
        self.loadOptions = options
        self.contextLength = effectiveContext
        self.threadCount = threads
        self.gpuLayers = effectiveGPULayers
        self.model = model
        self.context = context
        self.vocab = llama_model_get_vocab(model)
        self.batchSize = batch
        if let template = llama_model_chat_template(model, nil) {
            self.chatTemplate = String(cString: template)
        } else {
            self.chatTemplate = nil
        }
        modelLogger.info("Loaded \(info.name, privacy: .public) ctx=\(effectiveContext) threads=\(threads) gpuLayers=\(effectiveGPULayers)")
    }

    deinit {
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
    }

    /// Releases the weights and context. The instance is unusable afterwards.
    public func unload() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                activeGeneration?.cancel()
                if let context { llama_free(context) }
                if let model { llama_model_free(model) }
                context = nil
                model = nil
                continuation.resume()
            }
        }
    }

    /// Number of tokens the formatted chat occupies, including template control tokens.
    public func countTokens(for messages: [LlamaChatMessage]) async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    let prompt = try formatPrompt(messages)
                    continuation.resume(returning: try tokenize(prompt, addSpecial: true).count)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Number of tokens in a raw string, without template formatting.
    public func countTokens(in text: String) async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    continuation.resume(returning: try tokenize(text, addSpecial: false).count)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Streams a completion for the chat. Cancelling the consuming task stops generation
    /// within one token; the stream then ends with a `.finished` event carrying `.cancelled`.
    public func generate(messages: [LlamaChatMessage], options: LlamaSamplingOptions) -> AsyncThrowingStream<LlamaGenerationEvent, Error> {
        let flag = CancellationFlag()
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { _ in flag.cancel() }
            queue.async { [self] in
                activeGeneration = flag
                defer { activeGeneration = nil }
                do {
                    try runGeneration(messages: messages, options: options, flag: flag, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Queue-confined implementation

    private func runGeneration(
        messages: [LlamaChatMessage],
        options: LlamaSamplingOptions,
        flag: CancellationFlag,
        continuation: AsyncThrowingStream<LlamaGenerationEvent, Error>.Continuation
    ) throws {
        guard let context else { throw LlamaError.modelUnloaded }
        llama_set_abort_callback(context, abortCallback, Unmanaged.passUnretained(flag).toOpaque())
        defer { llama_set_abort_callback(context, nil, nil) }

        let prompt = try formatPrompt(messages)
        var tokens = try tokenize(prompt, addSpecial: true)
        let reserve = min(options.maxTokens, 16)
        guard tokens.count + reserve <= contextLength else {
            throw LlamaError.promptTooLong(tokens: tokens.count, limit: contextLength)
        }

        llama_memory_clear(llama_get_memory(context), true)
        let sampler = makeSampler(options)
        defer { llama_sampler_free(sampler) }

        let promptStart = DispatchTime.now()
        var offset = 0
        while offset < tokens.count {
            if flag.isCancelled {
                finish(continuation, stats: LlamaGenerationStats(promptTokens: tokens.count, generatedTokens: 0, promptSeconds: elapsed(since: promptStart), generationSeconds: 0, finishReason: .cancelled))
                return
            }
            let count = min(batchSize, tokens.count - offset)
            let result = tokens.withUnsafeMutableBufferPointer { buffer in
                llama_decode(context, llama_batch_get_one(buffer.baseAddress! + offset, Int32(count)))
            }
            if result == 2 {
                finish(continuation, stats: LlamaGenerationStats(promptTokens: tokens.count, generatedTokens: 0, promptSeconds: elapsed(since: promptStart), generationSeconds: 0, finishReason: .cancelled))
                return
            }
            guard result == 0 else { throw LlamaError.decodeFailed(code: result) }
            offset += count
        }
        let promptSeconds = elapsed(since: promptStart)
        continuation.yield(.promptProcessed(tokenCount: tokens.count, seconds: promptSeconds))

        var assembler = UTF8Assembler()
        var pieceBuffer = [CChar](repeating: 0, count: 512)
        var position = tokens.count
        var generated = 0
        var reason = LlamaFinishReason.maxTokens
        let generationStart = DispatchTime.now()

        while generated < options.maxTokens {
            if flag.isCancelled {
                reason = .cancelled
                break
            }
            if position >= contextLength {
                reason = .contextFull
                break
            }
            var token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) {
                reason = .endOfGeneration
                break
            }
            generated += 1

            let renderSpecial = options.rendersSpecialTokens
            var length = llama_token_to_piece(vocab, token, &pieceBuffer, Int32(pieceBuffer.count), 0, renderSpecial)
            if length < 0 {
                pieceBuffer = [CChar](repeating: 0, count: Int(-length) + 1)
                length = llama_token_to_piece(vocab, token, &pieceBuffer, Int32(pieceBuffer.count), 0, renderSpecial)
            }
            if length > 0 {
                let bytes = pieceBuffer[0..<Int(length)].map { UInt8(bitPattern: $0) }
                if let text = assembler.append(bytes), !text.isEmpty {
                    continuation.yield(.token(text))
                }
            }

            let result = llama_decode(context, llama_batch_get_one(&token, 1))
            if result == 2 {
                reason = .cancelled
                break
            }
            guard result == 0 else { throw LlamaError.decodeFailed(code: result) }
            position += 1
        }

        if let remainder = assembler.flush(), !remainder.isEmpty {
            continuation.yield(.token(remainder))
        }
        finish(continuation, stats: LlamaGenerationStats(
            promptTokens: tokens.count,
            generatedTokens: generated,
            promptSeconds: promptSeconds,
            generationSeconds: elapsed(since: generationStart),
            finishReason: reason
        ))
    }

    private func finish(_ continuation: AsyncThrowingStream<LlamaGenerationEvent, Error>.Continuation, stats: LlamaGenerationStats) {
        continuation.yield(.finished(stats))
        continuation.finish()
    }

    private func elapsed(since start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
    }

    private func makeSampler(_ options: LlamaSamplingOptions) -> UnsafeMutablePointer<llama_sampler> {
        var params = llama_sampler_chain_default_params()
        params.no_perf = true
        let chain = llama_sampler_chain_init(params)!
        if options.repeatPenalty > 1.0, options.repeatLastN > 0 {
            llama_sampler_chain_add(chain, llama_sampler_init_penalties(
                llama_vocab_n_tokens(vocab), Int32(options.repeatLastN), Float(options.repeatPenalty), 0, 0
            ))
        }
        if options.temperature <= 0 {
            llama_sampler_chain_add(chain, llama_sampler_init_greedy())
            return chain
        }
        if options.topK > 0 {
            llama_sampler_chain_add(chain, llama_sampler_init_top_k(Int32(options.topK)))
        }
        if options.topP < 1 {
            llama_sampler_chain_add(chain, llama_sampler_init_top_p(Float(options.topP), 1))
        }
        if options.minP > 0 {
            llama_sampler_chain_add(chain, llama_sampler_init_min_p(Float(options.minP), 1))
        }
        llama_sampler_chain_add(chain, llama_sampler_init_temp(Float(options.temperature)))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(options.seed ?? UInt32.random(in: 1..<UInt32.max)))
        return chain
    }

    private func formatPrompt(_ messages: [LlamaChatMessage]) throws -> String {
        guard let chatTemplate else {
            return ChatMLTemplate.render(messages)
        }
        let roles = messages.map { strdup($0.role)! }
        let contents = messages.map { strdup($0.content)! }
        defer {
            roles.forEach { free($0) }
            contents.forEach { free($0) }
        }
        let chat = zip(roles, contents).map { llama_chat_message(role: UnsafePointer($0), content: UnsafePointer($1)) }
        let estimate = max(1024, messages.reduce(0) { $0 + $1.content.utf8.count + $1.role.utf8.count + 64 } * 2)
        var buffer = [CChar](repeating: 0, count: estimate)
        var needed = llama_chat_apply_template(chatTemplate, chat, chat.count, true, &buffer, Int32(buffer.count))
        if needed < 0 {
            modelLogger.notice("Chat template not supported by llama.cpp; using ChatML fallback")
            return ChatMLTemplate.render(messages)
        }
        if Int(needed) > buffer.count {
            buffer = [CChar](repeating: 0, count: Int(needed) + 1)
            needed = llama_chat_apply_template(chatTemplate, chat, chat.count, true, &buffer, Int32(buffer.count))
            guard needed >= 0 else { throw LlamaError.chatTemplateFailed }
        }
        let bytes = buffer[0..<Int(needed)].map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func tokenize(_ text: String, addSpecial: Bool) throws -> [llama_token] {
        let length = Int32(text.utf8.count)
        var tokens = [llama_token](repeating: 0, count: Int(length) + 16)
        var count = text.withCString { cString in
            llama_tokenize(vocab, cString, length, &tokens, Int32(tokens.count), addSpecial, true)
        }
        if count == Int32.min {
            throw LlamaError.tokenizationFailed
        }
        if count < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-count))
            count = text.withCString { cString in
                llama_tokenize(vocab, cString, length, &tokens, Int32(tokens.count), addSpecial, true)
            }
            guard count >= 0 else { throw LlamaError.tokenizationFailed }
        }
        return Array(tokens.prefix(Int(count)))
    }
}
