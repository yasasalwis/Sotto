import SwiftData
import SwiftUI
import os

/// Runs one prompt through two models with the same seed and shows the answers side by side.
@Observable
final class CompareRunner {
    struct Slot: Identifiable {
        enum Status: Equatable { case idle, running, done, failed(String) }
        var id: Int
        var ref: ModelRef
        var text = ""
        var status: Status = .idle
        var latency: Double?
        var tokensPerSecond: Double?
        var tokens: Int?
    }

    var prompt = ""
    var slots: [Slot]
    var seed: UInt32 = UInt32.random(in: 1..<UInt32.max)
    private(set) var isRunning = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored let services: AppServices

    init(services: AppServices, refs: [ModelRef]) {
        self.services = services
        var initial = refs
        if initial.isEmpty { initial = [.apple] }
        if initial.count == 1 { initial.append(initial[0]) }
        slots = [Slot(id: 0, ref: initial[0]), Slot(id: 1, ref: initial[1])]
    }

    var hasRun: Bool { slots.contains { $0.status != .idle } }

    func stop() { task?.cancel() }

    func run(installed: [InstalledModel]) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, task == nil else { return }
        seed = UInt32.random(in: 1..<UInt32.max)
        for index in slots.indices {
            slots[index].text = ""
            slots[index].status = .running
            slots[index].latency = nil
            slots[index].tokensPerSecond = nil
            slots[index].tokens = nil
        }
        let sequential = slots[0].ref.ggufID != nil && slots[1].ref.ggufID != nil && slots[0].ref != slots[1].ref
        isRunning = true
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.task = nil
                self.isRunning = false
            }
            if sequential {
                await self.runSlot(0, prompt: trimmed, installed: installed)
                await self.runSlot(1, prompt: trimmed, installed: installed)
            } else {
                async let first: Void = self.runSlot(0, prompt: trimmed, installed: installed)
                async let second: Void = self.runSlot(1, prompt: trimmed, installed: installed)
                _ = await (first, second)
            }
        }
    }

    private func runSlot(_ index: Int, prompt: String, installed: [InstalledModel]) async {
        do {
            let engine = try ModelRegistry.engine(for: slots[index].ref, installed: installed, runtime: services.runtime)
            var sampling = SamplingSettings.default
            sampling.maxTokens = 512
            let request = GenerationRequest(systemPrompt: nil, turns: [ChatTurn(role: .user, content: prompt)], sampling: sampling, seed: seed)
            for try await event in engine.generate(request) {
                switch event {
                case .promptReady:
                    break
                case .delta(let delta):
                    slots[index].text += delta
                case .replace(let text):
                    slots[index].text = text
                case .finished(let outcome):
                    slots[index].latency = outcome.totalSeconds
                    slots[index].tokensPerSecond = outcome.tokensPerSecond
                    slots[index].tokens = outcome.generatedTokens
                    slots[index].status = .done
                }
            }
            if slots[index].status == .running { slots[index].status = .done }
        } catch is CancellationError {
            slots[index].status = .done
        } catch {
            slots[index].status = .failed(error.localizedDescription)
        }
    }
}

struct CompareView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \InstalledModel.importedAt, order: .reverse) private var installed: [InstalledModel]
    @State private var runner: CompareRunner?

    var body: some View {
        Group {
            if let runner {
                content(runner)
            } else {
                Color.clear
            }
        }
        .background(Theme.Colors.surface)
        .onAppear {
            if runner == nil {
                let created = CompareRunner(services: services, refs: services.state.compareModelRefs)
                created.prompt = services.state.comparePrompt ?? ""
                runner = created
                services.state.comparePrompt = nil
            }
        }
        .onDisappear { runner?.stop() }
        #if os(iOS)
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }.foregroundStyle(Theme.Colors.textSecondary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(runner?.isRunning == true ? "Stop" : "Run") {
                    guard let runner else { return }
                    runner.isRunning ? runner.stop() : runner.run(installed: installed)
                }
                .font(Theme.Fonts.mono(11))
                .foregroundStyle(Theme.Colors.accent)
            }
        }
        #endif
    }

    private func content(_ runner: CompareRunner) -> some View {
        @Bindable var runner = runner
        return VStack(spacing: 0) {
            #if os(macOS)
            HStack(spacing: 14) {
                TextField("Ask both models the same thing…", text: $runner.prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Theme.Fonts.sans(15))
                    .foregroundStyle(Theme.Colors.ink)
                    .lineLimit(1...4)
                    .onSubmit { runner.run(installed: installed) }
                    .accessibilityIdentifier("compare.prompt")
                MonoText("same prompt · same seed", size: 11)
                Button(runner.isRunning ? "Stop" : (runner.hasRun ? "Run again" : "Run")) {
                    runner.isRunning ? runner.stop() : runner.run(installed: installed)
                }
                .buttonStyle(PrimaryButtonStyle(size: 13, horizontalPadding: 14, verticalPadding: 7))
                .accessibilityIdentifier("compare.run")
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, 26)
            .padding(.bottom, 20)
            .hairlineDivider()
            HStack(spacing: 0) {
                slotView(runner, index: 0)
                    .overlay(alignment: .trailing) { Rectangle().fill(Theme.Colors.hairline).frame(width: 1) }
                slotView(runner, index: 1)
            }
            #else
            TextField("Ask both models the same thing…", text: $runner.prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Theme.Fonts.sans(15))
                .foregroundStyle(Theme.Colors.ink)
                .lineLimit(1...4)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(Theme.Colors.panel)
                .hairlineDivider(Theme.Colors.hairlineSoft)
                .accessibilityIdentifier("compare.prompt")
            VStack(spacing: 0) {
                slotView(runner, index: 0)
                    .hairlineDivider(Theme.Colors.hairlineSoft)
                slotView(runner, index: 1)
            }
            HStack {
                SectionLabel("Tap a name to swap models", size: 10)
                Spacer()
                HStack(spacing: 5) {
                    StatusDot(color: Theme.Colors.accent)
                    StatusDot(color: Theme.Colors.borderStrong)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .overlay(alignment: .top) { Rectangle().fill(Theme.Colors.hairlineSoft).frame(height: 1) }
            #endif
        }
    }

    private func slotView(_ runner: CompareRunner, index: Int) -> some View {
        let slot = runner.slots[index]
        let descriptor = ModelRegistry.descriptor(for: slot.ref, installed: installed, runtime: services.runtime)
        let other = runner.slots[1 - index]
        let isFaster = (slot.latency ?? .infinity) <= (other.latency ?? .infinity)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                StatusDot(color: isFaster && slot.status == .done ? Theme.Colors.accent : Theme.Colors.hint)
                modelMenu(runner, index: index, descriptor: descriptor)
                Spacer()
                MonoText(timing(slot), size: 10, color: isFaster && slot.status == .done ? Theme.Colors.accent : Theme.Colors.hint)
            }
            .padding(.horizontal, slotPadding)
            .padding(.vertical, 16)
            .background(Theme.Colors.panel)
            .hairlineDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    if slot.status == .running, slot.text.isEmpty {
                        TypingDots()
                    }
                    if !slot.text.isEmpty {
                        MarkdownBlocksView(text: slot.text, fontSize: 14, lineSpacing: 5, spacing: 13)
                    }
                    if case .failed(let message) = slot.status {
                        Text(message).font(Theme.Fonts.sans(13)).foregroundStyle(Theme.Colors.danger)
                    }
                    if slot.status == .done, let tokens = slot.tokens, let otherTokens = other.tokens, tokens > otherTokens {
                        MonoText("\(tokens) tokens · \(wordCount(slot.text) - wordCount(other.text)) words longer", size: 12)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, slotPadding)
                .padding(.vertical, 20)
            }
            HStack(spacing: 8) {
                Button("keep this one") { keep(slot, continueChat: false) }
                    .buttonStyle(ChipButtonStyle(active: isFaster && slot.status == .done))
                    .disabled(slot.status != .done || slot.text.isEmpty)
                #if os(macOS)
                Button("continue chat here") { keep(slot, continueChat: true) }
                    .buttonStyle(ChipButtonStyle())
                    .disabled(slot.status != .done || slot.text.isEmpty)
                #endif
            }
            .padding(.horizontal, slotPadding)
            .padding(.vertical, 16)
            .overlay(alignment: .top) { Rectangle().fill(Theme.Colors.hairline).frame(height: 1) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func modelMenu(_ runner: CompareRunner, index: Int, descriptor: ModelDescriptor?) -> some View {
        Menu {
            ForEach(ModelRegistry.all(installed: installed, runtime: services.runtime)) { candidate in
                Button(candidate.isAvailable ? "\(candidate.name) · \(candidate.detail)" : "\(candidate.name) — \(candidate.unavailableReason ?? "unavailable")") {
                    runner.slots[index].ref = candidate.ref
                    runner.slots[index].status = .idle
                    runner.slots[index].text = ""
                }
                .disabled(!candidate.isAvailable)
            }
        } label: {
            HStack(spacing: 8) {
                Text(descriptor?.name ?? "Choose model").font(Theme.Fonts.sans(14, weight: .medium)).foregroundStyle(Theme.Colors.ink)
                MonoText(descriptor?.detail ?? "", size: 11)
                Text("▾").font(.system(size: 9)).foregroundStyle(Theme.Colors.placeholder)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(runner.isRunning)
    }

    private var slotPadding: CGFloat {
        #if os(macOS)
        return 34
        #else
        return 18
        #endif
    }

    private func timing(_ slot: CompareRunner.Slot) -> String {
        guard let latency = slot.latency else { return slot.status == .running ? "running" : "" }
        if let tps = slot.tokensPerSecond {
            return "\(Format.seconds(latency)) · \(Format.tokensPerSecond(tps, fractionDigits: 0))"
        }
        return Format.seconds(latency)
    }

    private func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// Saves the chosen answer as a new conversation and, optionally, switches to it.
    private func keep(_ slot: CompareRunner.Slot, continueChat: Bool) {
        guard let runner else { return }
        let conversation = Conversation(modelRef: slot.ref)
        conversation.title = ChatSession.title(from: runner.prompt)
        conversation.isTitleGenerated = true
        let user = Message(role: .user, text: runner.prompt)
        let assistant = Message(role: .assistant, text: slot.text, createdAt: Date().addingTimeInterval(0.001), modelRef: slot.ref)
        assistant.latencySeconds = slot.latency
        assistant.tokensPerSecond = slot.tokensPerSecond
        assistant.generatedTokens = slot.tokens
        assistant.modelLabel = ModelRegistry.descriptor(for: slot.ref, installed: installed, runtime: services.runtime)?.shortLabel
        context.insert(conversation)
        conversation.messages.append(user)
        conversation.messages.append(assistant)
        try? context.save()
        services.state.selectedConversationID = conversation.id
        Log.chat.info("Kept compare result as a conversation")
        if continueChat {
            dismiss()
        }
        #if os(iOS)
        dismiss()
        #endif
    }
}
