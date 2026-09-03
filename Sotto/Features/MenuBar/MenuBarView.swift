#if os(macOS)
import AppKit
import SwiftData
import SwiftUI

/// The menu bar popover: ask a quick question, jump back into a recent chat, or open any of
/// Sotto's windows without first hunting for the app.
///
/// Nothing here streams a reply. A prompt typed in the field opens the chat window and is sent
/// there, so tool approval, attachments, retries and the transcript all stay in one place.
struct MenuBarView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]
    @Query(sort: \InstalledModel.importedAt, order: .reverse) private var installed: [InstalledModel]
    @State private var draft = ""
    @FocusState private var promptFocused: Bool

    private var isReady: Bool {
        services.lock.status == .unlocked && services.settings.hasCompletedOnboarding
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isReady {
                composer
                HairlineRule()
                chatSection
            } else {
                notice
            }
            HairlineRule()
            windowSection
            HairlineRule()
            footer
        }
        .frame(width: 272)
        .background(Theme.Colors.surface)
    }

    // MARK: - Ask

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Ask Sotto…", text: $draft)
                    .textFieldStyle(.plain)
                    .font(Theme.Fonts.sans(13))
                    .foregroundStyle(Theme.Colors.text)
                    .focused($promptFocused)
                    .onSubmit(send)
                    .accessibilityIdentifier("menuBar.prompt")
                Button(action: send) {
                    MonoText("⏎", size: 12, color: canSend ? Theme.Colors.accent : Theme.Colors.sendDisabledForeground)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(Theme.Colors.surfaceWarm)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .stroke(Theme.Colors.borderMedium, lineWidth: 1)
                    )
            )
            MonoText(statusLine, size: 10, color: Theme.Colors.placeholder)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .onAppear { promptFocused = true }
    }

    private var canSend: Bool { MenuBarModel.prompt(from: draft) != nil }

    /// The model a new chat would use, and what the runtime is doing right now.
    private var statusLine: String {
        let ref = ModelRegistry.preferredDefault(installed: installed, settings: services.settings)
        let name = ModelRegistry.descriptor(for: ref, installed: installed, runtime: services.runtime)?.name ?? "no model"
        let detail = MenuBarModel.statusDetail(state: services.runtime.state, isGenerating: services.runtime.isGenerating)
        return "\(name) · \(detail)"
    }

    /// Shown instead of the field when a prompt could not be answered anyway. The lock case
    /// also keeps conversation titles off screen while Sotto is locked.
    private var notice: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(services.lock.status == .unlocked ? "Finish setting up Sotto" : "Sotto is locked")
                .font(Theme.Fonts.sans(13, weight: .medium))
                .foregroundStyle(Theme.Colors.ink)
            Text(services.lock.status == .unlocked
                 ? "Open the window to choose a model and start chatting."
                 : "Unlock the window to see your chats and ask a question.")
                .font(Theme.Fonts.sans(11))
                .foregroundStyle(Theme.Colors.hint)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Sotto") { showWindow() }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    // MARK: - Chats

    private var chatSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            MenuBarRow(title: "New Chat", detail: "⌘N", action: newChat)
                .accessibilityIdentifier("menuBar.newChat")
            let recents = MenuBarModel.recents(conversations)
            if !recents.isEmpty {
                SectionLabel("Recent")
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                ForEach(recents) { conversation in
                    MenuBarRow(
                        title: conversation.title,
                        detail: ModelRegistry.descriptor(for: conversation.modelRef, installed: installed, runtime: services.runtime)?.shortLabel
                    ) {
                        open(conversation)
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }

    // MARK: - Windows

    private var windowSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            MenuBarRow(title: "Model Library…", detail: "⇧⌘L") { open(window: WindowID.library) }
            MenuBarRow(title: "Compare…", detail: "⇧⌘K") { open(window: WindowID.compare) }
            MenuBarRow(title: "Tools…", detail: "⇧⌘T") { open(window: WindowID.tools) }
            MenuBarRow(title: "Presets & Personas…", detail: "⇧⌘P") { open(window: WindowID.personas) }
            MenuBarRow(title: "Settings…", detail: "⌘,", action: showSettings)
                .accessibilityIdentifier("menuBar.settings")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            MenuBarRow(
                title: "Unload Model",
                detail: services.runtime.loadedModel == nil ? nil : "frees memory",
                isEnabled: services.runtime.loadedModel != nil,
                action: unload
            )
            MenuBarRow(title: "Quit Sotto", detail: "⌘Q") { NSApp.terminate(nil) }
                .accessibilityIdentifier("menuBar.quit")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }

    // MARK: - Actions

    /// Hands the prompt to a fresh chat and opens the window, which sends it.
    private func send() {
        guard let prompt = MenuBarModel.prompt(from: draft) else { return }
        draft = ""
        services.startQuickPrompt(prompt)
        showWindow()
    }

    private func newChat() {
        services.startConversation()
        showWindow()
    }

    private func open(_ conversation: Conversation) {
        services.state.selectedConversationID = conversation.id
        showWindow()
    }

    private func showWindow() {
        MainWindow.show(openWindow)
        dismiss()
    }

    private func open(window id: String) {
        openWindow(id: id)
        NSApp.activate()
        dismiss()
    }

    private func showSettings() {
        openSettings()
        NSApp.activate()
        dismiss()
    }

    private func unload() {
        Task { await services.runtime.unload() }
        dismiss()
    }
}

/// One line of the popover: a title, an optional mono hint, and a hover highlight.
private struct MenuBarRow: View {
    let title: String
    var detail: String?
    var isEnabled = true
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(Theme.Fonts.sans(13))
                    .foregroundStyle(isEnabled ? Theme.Colors.text : Theme.Colors.disabledText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                if let detail {
                    MonoText(detail, size: 10, color: isEnabled ? Theme.Colors.placeholder : Theme.Colors.disabledText)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(isHovering && isEnabled ? Theme.Colors.accentPale : Color.clear)
            )
        }
        .buttonStyle(PlainRowButtonStyle())
        .disabled(!isEnabled)
        .onHover { isHovering = $0 }
    }
}
#endif
