import Foundation
import Observation
import SwiftData
import os

/// Drives one conversation: composing, sending, streaming, retrying and switching models.
@Observable
final class ChatSession {
    let conversation: Conversation
    @ObservationIgnored let services: AppServices
    @ObservationIgnored let context: ModelContext

    var draft = ""
    var attachments: [Attachment] = []
    private(set) var streamingMessageID: UUID?
    private(set) var isGenerating = false
    private(set) var contextTokensUsed = 0
    private(set) var droppedTurns = 0
    var lastError: String?

    @ObservationIgnored private var generationTask: Task<Void, Never>?

    init(conversation: Conversation, services: AppServices, context: ModelContext) {
        self.conversation = conversation
        self.services = services
        self.context = context
        self.contextTokensUsed = Self.estimateHistoryTokens(conversation)
    }

    var persona: Persona? {
        guard let id = conversation.personaID else { return nil }
        var descriptor = FetchDescriptor<Persona>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    var installedModels: [InstalledModel] {
        (try? context.fetch(FetchDescriptor<InstalledModel>(sortBy: [SortDescriptor(\.importedAt, order: .reverse)]))) ?? []
    }

    var modelDescriptor: ModelDescriptor? {
        ModelRegistry.descriptor(for: conversation.modelRef, installed: installedModels, runtime: services.runtime)
    }

    var contextLength: Int {
        modelDescriptor?.contextLength ?? AppleIntelligenceEngine.fixedContextLength
    }

    /// Tokens the history plus the current draft would occupy, for the composer counter.
    var projectedTokens: Int {
        contextTokensUsed + TokenEstimator.estimate(draft) + attachments.reduce(0) { $0 + TokenEstimator.estimate($1.text) }
    }

    var canSend: Bool {
        !isGenerating && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
    }

    // MARK: - Actions

    func send() {
        guard canSend else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachmentText = attachments.isEmpty ? nil : attachments.map { "### \($0.name)\n\($0.text)" }.joined(separator: "\n\n")
        let user = Message(
            role: .user,
            text: text.isEmpty ? "Summarize the attached file." : text,
            attachmentNames: attachments.map(\.name),
            attachmentText: attachmentText
        )
        conversation.messages.append(user)
        if !conversation.isTitleGenerated {
            conversation.title = Self.title(from: user.text)
            conversation.isTitleGenerated = true
        }
        draft = ""
        attachments = []
        lastError = nil
        conversation.updatedAt = .now
        if let persona { persona.usageCount += 1 }
        let assistant = Message(role: .assistant, text: "", modelRef: conversation.modelRef, state: .streaming)
        conversation.messages.append(assistant)
        save()
        respond(into: assistant, boundary: assistant, modelRef: conversation.modelRef)
    }

    func stop() {
        generationTask?.cancel()
    }

    /// Regenerates an assistant message in place with the same model and context.
    func retry(_ message: Message) {
        guard !isGenerating, message.role == .assistant else { return }
        let ref = message.modelRef ?? conversation.modelRef
        respond(into: message, boundary: message, modelRef: ref)
    }

    /// Answers the same prompt with a different model, adding the result right after `message`.
    func tryOn(_ message: Message, ref: ModelRef) {
        guard !isGenerating, message.role == .assistant else { return }
        let sibling = Message(role: .assistant, text: "", createdAt: message.createdAt.addingTimeInterval(0.001), modelRef: ref, state: .streaming)
        conversation.messages.append(sibling)
        save()
        respond(into: sibling, boundary: message, modelRef: ref)
    }

    func delete(_ message: Message) {
        guard streamingMessageID != message.id else { return }
        context.delete(message)
        save()
        contextTokensUsed = Self.estimateHistoryTokens(conversation)
    }

    func attach(_ url: URL) {
        do {
            let attachment = try AttachmentReader.read(url)
            attachments.append(attachment)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func removeAttachment(_ attachment: Attachment) {
        attachments.removeAll { $0 == attachment }
    }

    func setModel(_ ref: ModelRef) {
        conversation.modelRef = ref
        save()
    }

    func setPersona(_ persona: Persona?) {
        conversation.personaID = persona?.id
        if let ref = persona?.modelRef, installedModels.contains(where: { $0.modelRef == ref }) || ref.isApple {
            conversation.modelRef = ref
        }
        save()
    }

    /// Models other than the one that produced `message`, offered as "try on …" chips.
    func alternatives(to message: Message) -> [ModelDescriptor] {
        let current = message.modelRef ?? conversation.modelRef
        return ModelRegistry.all(installed: installedModels, runtime: services.runtime)
            .filter { $0.ref != current && $0.isAvailable }
    }

    // MARK: - Generation

    private func respond(into assistant: Message, boundary: Message, modelRef: ModelRef) {
        assistant.state = .streaming
        assistant.text = ""
        assistant.errorMessage = nil
        assistant.modelRef = modelRef
        streamingMessageID = assistant.id
        lastError = nil
        isGenerating = true
        generationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.generationTask = nil
                self.streamingMessageID = nil
                self.isGenerating = false
            }
            await self.runGeneration(into: assistant, boundary: boundary, modelRef: modelRef)
        }
    }

    private func runGeneration(into assistant: Message, boundary: Message, modelRef: ModelRef) async {
        do {
            let installed = installedModels
            let engine = try ModelRegistry.engine(for: modelRef, installed: installed, runtime: services.runtime)
            assistant.modelLabel = ModelRegistry.descriptor(for: modelRef, installed: installed, runtime: services.runtime)?.shortLabel
            let sampling = SamplingSettings.resolve(persona: persona, conversation: conversation)
            let turns = PromptBuilder.turns(from: conversation.orderedMessages, upTo: boundary)
            let built = try await PromptBuilder.build(
                turns: turns,
                systemPrompt: persona?.systemPrompt,
                sampling: sampling,
                contextLength: engine.contextLength
            ) { text in
                try await engine.countTokens(text)
            }
            droppedTurns = built.droppedTurns
            var promptTokens = built.estimatedPromptTokens
            Log.chat.info("Generating with \(engine.displayName, privacy: .public): \(built.request.turns.count) turns, ~\(promptTokens) prompt tokens, dropped \(built.droppedTurns)")

            for try await event in engine.generate(built.request) {
                switch event {
                case .promptReady(let tokens):
                    if let tokens { promptTokens = tokens }
                case .delta(let delta):
                    assistant.text += delta
                case .replace(let text):
                    assistant.text = text
                case .finished(let outcome):
                    assistant.latencySeconds = outcome.totalSeconds
                    assistant.tokensPerSecond = outcome.tokensPerSecond
                    assistant.promptTokens = outcome.promptTokens ?? promptTokens
                    assistant.generatedTokens = outcome.generatedTokens
                    assistant.state = outcome.finishReason == .cancelled ? .cancelled : .complete
                    if modelRef.isApple, let tps = outcome.tokensPerSecond {
                        AppleThroughput.record(tps)
                    }
                    contextTokensUsed = (outcome.promptTokens ?? promptTokens) + (outcome.generatedTokens ?? TokenEstimator.estimate(assistant.text))
                    services.runtime.recordContextUsage(tokens: contextTokensUsed, contextLength: engine.contextLength)
                    Log.chat.info("Finished: \(outcome.finishReason.rawValue, privacy: .public) in \(String(format: "%.2f", outcome.totalSeconds), privacy: .public)s")
                }
            }
            if assistant.state == .streaming {
                assistant.state = .complete
            }
        } catch is CancellationError {
            assistant.state = .cancelled
        } catch {
            assistant.state = assistant.text.isEmpty ? .failed : .complete
            assistant.errorMessage = error.localizedDescription
            lastError = error.localizedDescription
            Log.chat.error("Generation failed: \(error.localizedDescription, privacy: .public)")
        }
        conversation.updatedAt = .now
        save()
    }

    private func save() {
        do {
            try context.save()
        } catch {
            Log.persistence.error("Saving conversation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func title(from text: String) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: .punctuationCharacters)
        guard !trimmed.isEmpty else { return "New chat" }
        if trimmed.count <= 42 { return trimmed }
        let cut = trimmed.prefix(42)
        if let space = cut.lastIndex(of: " ") {
            return String(cut[..<space]) + "…"
        }
        return String(cut) + "…"
    }

    static func estimateHistoryTokens(_ conversation: Conversation) -> Int {
        conversation.messages.reduce(0) { $0 + TokenEstimator.estimate($1.promptText) + PromptBuilder.perTurnOverheadTokens }
    }
}
