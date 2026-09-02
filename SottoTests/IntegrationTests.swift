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
}
