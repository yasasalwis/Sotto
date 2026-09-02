import Foundation
import Observation
import SwiftData
import os

enum ToolApprovalDecision: Sendable {
    case allowOnce
    case allowAlways
    case deny
}

/// A tool call waiting for the user's decision, surfaced as a card in the chat.
struct PendingToolApproval: Identifiable {
    let id: UUID
    let toolName: String
    let displayName: String
    let kind: ToolKind
    let argumentsSummary: String
    /// What actually happens: the address to be called, or the command to be run.
    let effect: String
    let resolve: (ToolApprovalDecision) -> Void
}

/// Drives one conversation: composing, sending, streaming, retrying and switching models.
@Observable
final class ChatSession: ToolRunner {
    let conversation: Conversation
    @ObservationIgnored let services: AppServices
    @ObservationIgnored let context: ModelContext

    var draft = ""
    var attachments: [Attachment] = []
    private(set) var streamingMessageID: UUID?
    private(set) var isGenerating = false
    /// Set while a tool call is waiting for approval.
    var pendingToolApproval: PendingToolApproval?
    private(set) var contextTokensUsed = 0
    private(set) var droppedTurns = 0
    var lastError: String?

    @ObservationIgnored private var generationTask: Task<Void, Never>?
    @ObservationIgnored private var currentAssistant: Message?
    @ObservationIgnored private var toolCallsThisTurn = 0

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

    /// Tools this conversation may use: enabled, runnable here, and permitted by the persona.
    var availableTools: [ToolDefinition] {
        guard services.settings.toolsEnabled else { return [] }
        let descriptor = FetchDescriptor<ToolDefinition>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)])
        let usable = ((try? context.fetch(descriptor)) ?? []).filter(\.isUsable)
        guard let persona else { return usable }
        return persona.tools(from: usable)
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
        pendingToolApproval?.resolve(.deny)
        generationTask?.cancel()
    }

    /// Answers a pending approval card.
    func resolveToolApproval(_ decision: ToolApprovalDecision) {
        guard let pending = pendingToolApproval else { return }
        pendingToolApproval = nil
        pending.resolve(decision)
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
            let tools = availableTools
            var request = built.request
            request.tools = tools.map(\.spec)
            currentAssistant = assistant
            toolCallsThisTurn = 0
            Log.chat.info("Generating with \(engine.displayName, privacy: .public): \(built.request.turns.count) turns, ~\(promptTokens) prompt tokens, dropped \(built.droppedTurns), \(tools.count) tools")

            for try await event in engine.generate(request, toolRunner: tools.isEmpty ? nil : self) {
                switch event {
                case .promptReady(let tokens):
                    if let tokens { promptTokens = tokens }
                case .delta(let delta):
                    assistant.text += delta
                case .replace(let text):
                    assistant.text = text
                case .toolCall, .toolResult:
                    // The runner below records the call; nothing extra to do here.
                    break
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
        pendingToolApproval?.resolve(.deny)
        pendingToolApproval = nil
        currentAssistant = nil
        conversation.updatedAt = .now
        save()
    }

    // MARK: - ToolRunner

    /// Resolves the tool, asks for approval when required, runs it and records the outcome on the
    /// assistant message being produced.
    func run(_ call: ToolCallRequest) async -> ToolRunResult {
        let tools = availableTools
        guard let definition = tools.first(where: { $0.name == call.name }) else {
            let names = tools.map(\.name).joined(separator: ", ")
            Log.chat.notice("Model asked for unknown tool \(call.name, privacy: .public)")
            return ToolRunResult(
                text: "Error: there is no tool called “\(call.name)”.\(names.isEmpty ? "" : " Available tools: \(names).")",
                success: false, denied: false, bytesSent: 0, durationSeconds: 0
            )
        }
        guard toolCallsThisTurn < ToolDefinition.maximumCallsPerTurn else {
            return ToolRunResult(
                text: "Error: this reply has already used its \(ToolDefinition.maximumCallsPerTurn) tool calls. Answer with what you have.",
                success: false, denied: false, bytesSent: 0, durationSeconds: 0
            )
        }
        toolCallsThisTurn += 1

        var record = ToolCallRecord(
            toolName: definition.name,
            displayName: definition.displayName,
            argumentsJSON: call.argumentsJSON,
            status: definition.approval == .askEveryTime ? .awaitingApproval : .running
        )
        appendToolRecord(record)

        if definition.approval == .askEveryTime {
            let decision = await requestApproval(for: definition, call: call)
            switch decision {
            case .deny:
                record.status = .denied
                record.resultText = "You declined this tool call."
                updateToolRecord(record)
                save()
                Log.chat.info("Tool \(definition.name, privacy: .public) declined by the user")
                return .denied()
            case .allowAlways:
                definition.approval = .automatic
                definition.updatedAt = .now
            case .allowOnce:
                break
            }
            record.status = .running
            updateToolRecord(record)
        }

        let executor = ToolExecutor(settings: services.settings, context: context)
        let result = await executor.execute(definition, arguments: ToolExecutor.decodeArguments(call.argumentsJSON))
        definition.usageCount += 1
        definition.updatedAt = .now
        record.status = result.success ? .succeeded : .failed
        record.resultText = result.text
        record.durationSeconds = result.durationSeconds
        record.bytesSent = result.bytesSent
        updateToolRecord(record)
        save()
        return result
    }

    private func requestApproval(for definition: ToolDefinition, call: ToolCallRequest) async -> ToolApprovalDecision {
        let arguments = ToolExecutor.decodeArguments(call.argumentsJSON)
        let effect: String
        switch definition.kind {
        case .builtIn:
            effect = "Runs on this device."
        case .webSearch:
            let query = ToolTemplate.stringValue(arguments["query"]) ?? ""
            let site = definition.webSearchConfig?.site ?? ""
            effect = "Search Google for “\(query)”" + (site.isEmpty ? "" : " on \(site)")
        case .httpRequest:
            let url = ToolTemplate.substitute(definition.httpConfig?.urlTemplate ?? "", arguments: arguments) { $0 }
            effect = "\(definition.httpConfig?.method.uppercased() ?? "GET") \(url)"
        case .shellCommand:
            effect = ToolTemplate.substitute(definition.shellConfig?.command ?? "", arguments: arguments) { $0 }
        }
        return await withCheckedContinuation { continuation in
            let box = ApprovalBox(continuation)
            pendingToolApproval = PendingToolApproval(
                id: call.id,
                toolName: definition.name,
                displayName: definition.displayName,
                kind: definition.kind,
                argumentsSummary: ToolCallRecord(toolName: definition.name, displayName: definition.displayName, argumentsJSON: call.argumentsJSON).argumentsSummary,
                effect: effect,
                resolve: { decision in box.resume(decision) }
            )
        }
    }

    private func appendToolRecord(_ record: ToolCallRecord) {
        guard let assistant = currentAssistant else { return }
        var records = assistant.toolCalls
        records.append(record)
        assistant.toolCalls = records
    }

    private func updateToolRecord(_ record: ToolCallRecord) {
        guard let assistant = currentAssistant else { return }
        var records = assistant.toolCalls
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.append(record)
        }
        assistant.toolCalls = records
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

    /// A continuation may only be resumed once; the card and `stop()` can both answer it.
    private final class ApprovalBox: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<ToolApprovalDecision, Never>?

        init(_ continuation: CheckedContinuation<ToolApprovalDecision, Never>) {
            self.continuation = continuation
        }

        func resume(_ decision: ToolApprovalDecision) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: decision)
        }
    }

    static func estimateHistoryTokens(_ conversation: Conversation) -> Int {
        conversation.messages.reduce(0) { $0 + TokenEstimator.estimate($1.promptText) + PromptBuilder.perTurnOverheadTokens }
    }
}
