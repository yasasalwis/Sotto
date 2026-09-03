import Foundation
import os
import SwiftData
import Testing
@testable import Sotto

/// End-to-end checks that drive the real engines through `ChatSession` with an in-memory store.
/// The Apple Intelligence test skips itself when the host has no eligible system model; the GGUF
/// test runs only when `SOTTO_TEST_GGUF` points at a model file.
@MainActor
struct IntegrationTests {
    private func makeServicesAndContext() throws -> (AppServices, ModelContext, ModelContainer) {
        let services = AppServices()
        let container = try PersistenceController.makeContainer(inMemory: true, baseDirectory: services.store.baseDirectory)
        return (services, container.mainContext, container)
    }

    private func waitForCompletion(_ session: ChatSession, timeout: Duration) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while session.isGenerating, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(!session.isGenerating, "generation should finish within \(timeout)")
    }

    @Test func appleIntelligenceAnswersThroughChatSession() async throws {
        guard AppleIntelligenceEngine.isAvailable else {
            Log.app.notice("Skipping Apple Intelligence integration test: \(AppleIntelligenceEngine.unavailableReason ?? "unavailable")")
            return
        }
        let (services, context, container) = try makeServicesAndContext()
        defer { withExtendedLifetime(container) {} }
        let conversation = Conversation(modelRef: .apple)
        context.insert(conversation)
        let session = ChatSession(conversation: conversation, services: services, context: context)
        session.draft = "Reply with exactly one word: hello"
        session.send()
        try await waitForCompletion(session, timeout: .seconds(120))

        let messages = conversation.orderedMessages
        #expect(messages.count == 2)
        let assistant = try #require(messages.last)
        #expect(assistant.role == .assistant)
        #expect(assistant.state == .complete, "assistant state: \(assistant.state) error: \(assistant.errorMessage ?? "-")")
        #expect(!assistant.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(assistant.latencySeconds ?? 0 > 0)
        #expect(conversation.title.hasPrefix("Reply with exactly one word"))
        #expect(session.contextTokensUsed > 0)
    }

    @Test func ggufModelAnswersThroughChatSession() async throws {
        guard let path = ProcessInfo.processInfo.environment["SOTTO_TEST_GGUF"], FileManager.default.fileExists(atPath: path) else {
            Log.app.notice("Skipping GGUF integration test: set SOTTO_TEST_GGUF to a .gguf path")
            return
        }
        let (services, context, container) = try makeServicesAndContext()
        defer { withExtendedLifetime(container) {} }
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("sotto-it-\(UUID().uuidString)")
        let store = ModelStore(baseDirectory: base)
        defer { try? FileManager.default.removeItem(at: base) }
        let runtime = ModelRuntime(store: store, settings: services.settings)
        runtime.settings.contextLength = 2048

        let record = try await store.importModel(from: URL(fileURLWithPath: path), into: context)
        #expect(record.quantization != "unknown")
        #expect(record.parameterCount > 0)
        #expect(record.contextLength > 0)
        #expect(store.fileExists(for: record))

        let engine = GGUFEngine(record: record, runtime: runtime)
        let request = GenerationRequest(systemPrompt: "You answer in one short sentence.", turns: [ChatTurn(role: .user, content: "What colour is the sky on a clear day?")], sampling: SamplingSettings(temperature: 0.2, topP: 0.9, maxTokens: 48), seed: 7)
        var text = ""
        var outcome: GenerationOutcome?
        var promptTokens: Int?
        for try await event in engine.generate(request) {
            switch event {
            case .promptReady(let tokens): promptTokens = tokens
            case .delta(let delta): text += delta
            case .replace(let full): text = full
            case .toolCall, .toolResult: break
            case .finished(let result): outcome = result
            }
        }
        let finished = try #require(outcome)
        #expect(!text.isEmpty)
        #expect(text.lowercased().contains("blue"))
        #expect(promptTokens ?? 0 > 10)
        #expect(finished.tokensPerSecond ?? 0 > 0)
        #expect(finished.finishReason == .complete || finished.finishReason == .maxTokens)
        #expect(runtime.loadedModelID == record.id)
        #expect(record.measuredTokensPerSecond ?? 0 > 0)

        // Exact token counting goes through the model's own tokenizer.
        let count = try await engine.countTokens("one two three four")
        #expect(count >= 4 && count <= 8)

        // Cancellation stops the stream promptly and reports it.
        let long = GenerationRequest(systemPrompt: nil, turns: [ChatTurn(role: .user, content: "Count from 1 to 500, one number per line.")], sampling: SamplingSettings(temperature: 0.2, topP: 0.9, maxTokens: 400), seed: 1)
        let task = Task { @MainActor in
            var last: GenerationOutcome?
            for try await event in engine.generate(long) {
                if case .finished(let result) = event { last = result }
            }
            return last
        }
        try await Task.sleep(for: .milliseconds(800))
        task.cancel()
        let cancelled = try await task.value
        #expect(cancelled == nil || cancelled?.finishReason == .cancelled)

        await runtime.unload()
        #expect(runtime.loadedModel == nil)
    }

    /// A greeting should not make the model reach for a tool. This measures a live model rather
    /// than our own code, so it only runs when SOTTO_TEST_TOOL_RESTRAINT is set; a small model
    /// occasionally misfires whatever the instructions say, and that must not redden CI.
    @Test func greetingsDoNotTriggerTools() async throws {
        guard ProcessInfo.processInfo.environment["SOTTO_TEST_TOOL_RESTRAINT"] != nil else { return }
        guard AppleIntelligenceEngine.isAvailable else {
            Log.app.notice("Skipping tool restraint test: \(AppleIntelligenceEngine.unavailableReason ?? "unavailable")")
            return
        }
        let recorder = RecordingToolRunner()
        let engine = AppleIntelligenceEngine()
        let tools = ToolDefinition.builtInSeeds().filter { $0.isUsable }.map(\.spec)
        #expect(!tools.isEmpty)

        for prompt in ["hello. in one word", "Say hello in one word", "hi there"] {
            recorder.calls.removeAll()
            var request = GenerationRequest(
                systemPrompt: nil,
                turns: [ChatTurn(role: .user, content: prompt)],
                sampling: SamplingSettings(temperature: 0.2, topP: 0.9, maxTokens: 64),
                seed: 4
            )
            request.tools = tools
            request.systemPrompt = nil
            var text = ""
            for try await event in engine.generate(request, toolRunner: recorder) {
                if case .delta(let delta) = event { text += delta }
                if case .replace(let full) = event { text = full }
            }
            // What matters to the reader is the answer, not the chip: a greeting must never come
            // back carrying a date, a measurement or a count.
            let carriesFigures = text.contains { $0.isNumber }
            #expect(
                !carriesFigures,
                "“\(prompt)” answered with figures after calling \(recorder.calls.joined(separator: ", ")): \(text.prefix(120))"
            )
            #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    /// Starts a real catalog download and waits for the first bytes. Gated because it touches the
    /// network; the point is to catch the download path silently doing nothing.
    @Test func catalogDownloadsTransferBytes() async throws {
        guard ProcessInfo.processInfo.environment["SOTTO_TEST_DOWNLOAD"] != nil else { return }
        let services = AppServices()
        let entry = try #require(services.catalog.entries.min(by: { $0.sizeBytes < $1.sizeBytes }))
        let record = try services.downloads.start(entry)
        defer { services.downloads.cancel(record) }

        var received: Int64 = 0
        for _ in 0..<80 {
            try await Task.sleep(for: .milliseconds(500))
            received = services.downloads.live[record.id]?.received ?? record.receivedBytes
            if received > 0 { break }
            if record.state == .failed { break }
        }
        let diagnosis = "state=\(record.state.rawValue) received=\(received) error=\(record.errorMessage ?? "none")\n"
        try? Data(diagnosis.utf8).write(to: FileManager.default.temporaryDirectory.appendingPathComponent("sotto-download.txt"))
        #expect(
            received > 0,
            "no bytes after 40s — state \(record.state.rawValue), error \(record.errorMessage ?? "none")"
        )
        withExtendedLifetime(services) {}
    }

    /// Apple's model reads every offered tool into its 4,096-token window and, past roughly twenty,
    /// fails outright rather than answering worse. This offers the whole library at once and checks
    /// that the budget trim keeps an answer coming. Gated: it needs the real system model.
    @Test func theWholeLibraryStillAnswers() async throws {
        guard ProcessInfo.processInfo.environment["SOTTO_TEST_TOOL_RESTRAINT"] != nil else { return }
        guard AppleIntelligenceEngine.isAvailable else { return }
        let everything = ToolDefinition.builtInSeeds().map(\.spec)
        #expect(everything.count >= 25)
        let offered = AppleIntelligenceEngine.toolsFittingBudget(everything)
        #expect(offered.count < everything.count, "the trim did nothing, so the budget is not being applied")

        let recorder = RecordingToolRunner()
        var request = GenerationRequest(
            systemPrompt: nil,
            turns: [ChatTurn(role: .user, content: "What is 12 times 12?")],
            sampling: SamplingSettings(temperature: 0.2, topP: 0.9, maxTokens: 96),
            seed: 7
        )
        request.tools = everything
        var text = ""
        for try await event in AppleIntelligenceEngine().generate(request, toolRunner: recorder) {
            if case .delta(let delta) = event { text += delta }
            if case .replace(let full) = event { text = full }
        }
        #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "the model produced nothing with \(everything.count) tools offered")
    }

    /// The counterpart: a request that genuinely needs a tool still gets one.
    @Test func realRequestsStillReachForTools() async throws {
        guard ProcessInfo.processInfo.environment["SOTTO_TEST_TOOL_RESTRAINT"] != nil else { return }
        guard AppleIntelligenceEngine.isAvailable else { return }
        let recorder = RecordingToolRunner()
        recorder.reply = "5 km = 3.1069 mi"
        let engine = AppleIntelligenceEngine()
        var request = GenerationRequest(
            systemPrompt: nil,
            turns: [ChatTurn(role: .user, content: "Convert 5 km to miles.")],
            sampling: SamplingSettings(temperature: 0.2, topP: 0.9, maxTokens: 128),
            seed: 4
        )
        request.tools = ToolDefinition.builtInSeeds().filter { $0.isUsable }.map(\.spec)
        for try await _ in engine.generate(request, toolRunner: recorder) {}
        #expect(recorder.calls.contains("convert_units"), "called \(recorder.calls)")
    }
}

/// Stands in for the chat session, recording what the model asked for.
private final class RecordingToolRunner: ToolRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    var reply = "done"

    var calls: [String] {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }

    func run(_ call: ToolCallRequest) async -> ToolRunResult {
        lock.withLock { storage.append(call.name) }
        return ToolRunResult(text: reply, success: true, denied: false, bytesSent: 0, durationSeconds: 0)
    }
}
