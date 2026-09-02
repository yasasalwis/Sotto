import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ComposerView: View {
    @Bindable var session: ChatSession
    @Environment(AppServices.self) private var services
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \Persona.sortOrder) private var personas: [Persona]
    @FocusState private var focused: Bool

    private var placeholder: String {
        session.conversation.isEmpty ? "Message Sotto…" : "Reply…"
    }

    private var counter: String {
        "\(Format.integer(session.projectedTokens)) / \(Format.integer(session.contextLength))"
    }

    var body: some View {
        Group {
            #if os(macOS)
            macComposer
            #else
            iosComposer
            #endif
        }
        .fileImporter(isPresented: attachBinding, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                for url in urls { session.attach(url) }
            }
        }
        .alert("Couldn't attach", isPresented: Binding(get: { session.lastError != nil && !session.isGenerating && session.conversation.orderedMessages.last?.errorMessage == nil }, set: { if !$0 { session.lastError = nil } })) {
            Button("OK") { session.lastError = nil }
        } message: {
            Text(session.lastError ?? "")
        }
    }

    private var attachBinding: Binding<Bool> {
        Binding(get: { services.state.isAttachingFile }, set: { services.state.isAttachingFile = $0 })
    }

    // MARK: - macOS

    #if os(macOS)
    private var macComposer: some View {
        VStack(spacing: 14) {
            attachmentChips
            editor
            HStack(spacing: 10) {
                Button("＠ attach") { services.state.isAttachingFile = true }
                    .buttonStyle(ChipButtonStyle())
                    .accessibilityIdentifier("composer.attach")
                personaMenu
                Spacer()
                if services.settings.showTokenCounter {
                    MonoText(counter, size: 11, color: Theme.Colors.placeholder)
                        .accessibilityIdentifier("composer.counter")
                }
                sendButton(size: 30, radius: 8, iconSize: 14)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.composer, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.composer, style: .continuous).stroke(Theme.Colors.borderMedium, lineWidth: 1))
        .shadow(color: Color(hex: 0x141916, opacity: 0.08), radius: 5, y: 2)
        .padding(.horizontal, 44)
        .padding(.bottom, 30)
        .padding(.top, 8)
    }

    private var personaMenu: some View {
        Menu {
            Button("No persona") { session.setPersona(nil) }
            Divider()
            ForEach(personas) { persona in
                Button(persona.name) { session.setPersona(persona) }
            }
            Divider()
            Button("Edit presets…") { openWindow(id: WindowID.personas) }
        } label: {
            Text("persona: \(session.persona?.name.lowercased() ?? "default")")
        }
        .buttonStyle(ChipButtonStyle(active: session.persona != nil))
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityIdentifier("composer.persona")
    }
    #endif

    // MARK: - iOS

    #if os(iOS)
    private var iosComposer: some View {
        VStack(spacing: 10) {
            attachmentChips
            if !session.conversation.isEmpty || session.persona != nil {
                HStack(spacing: 8) {
                    Button("persona: \(session.persona?.name.lowercased() ?? "default")") {
                        services.state.sheet = .personaPicker
                    }
                    .buttonStyle(ChipButtonStyle(active: session.persona != nil, size: 10))
                    Button("＠ attach") { services.state.isAttachingFile = true }
                        .buttonStyle(ChipButtonStyle(size: 10))
                    Spacer()
                    if services.settings.showTokenCounter {
                        MonoText(counter, size: 10, color: Theme.Colors.placeholder)
                    }
                }
            }
            HStack(spacing: 10) {
                editor
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .frame(minHeight: 44)
                    .fixedSize(horizontal: false, vertical: true)
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.Colors.borderMedium, lineWidth: 1))
                sendButton(size: 44, radius: 22, iconSize: 17)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(Theme.Colors.surface)
        .overlay(alignment: .top) {
            if !session.conversation.isEmpty { Rectangle().fill(Theme.Colors.hairlineSoft).frame(height: 1) }
        }
    }
    #endif

    // MARK: - Shared pieces

    @ViewBuilder
    private var editor: some View {
        TextField(placeholder, text: $session.draft, axis: .vertical)
            .textFieldStyle(.plain)
            .font(Theme.Fonts.sans(editorFontSize))
            .foregroundStyle(Theme.Colors.ink)
            .lineLimit(1...8)
            .focused($focused)
            #if os(iOS)
            .submitLabel(.send)
            .onSubmit { session.send() }
            #else
            .onSubmit {
                // Return sends by default; when that's off it inserts a line and ⌘Return sends.
                if services.settings.sendWithEnter {
                    session.send()
                } else {
                    session.draft += "\n"
                }
            }
            .onKeyPress(.return, phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                session.send()
                return .handled
            }
            .onAppear { focused = true }
            #endif
            .accessibilityIdentifier("composer.editor")
    }

    private var editorFontSize: CGFloat {
        #if os(macOS)
        return 15
        #else
        return 16
        #endif
    }

    @ViewBuilder
    private var attachmentChips: some View {
        if !session.attachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(session.attachments, id: \.self) { attachment in
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text").font(.system(size: 10))
                            Text(attachment.name).font(Theme.Fonts.mono(10)).lineLimit(1)
                            MonoText("~\(Format.integer(TokenEstimator.estimate(attachment.text))) tok", size: 9, color: Theme.Colors.faint)
                            Button {
                                session.removeAttachment(attachment)
                            } label: {
                                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(attachment.name)")
                        }
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Theme.Colors.accentPale, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Theme.Colors.accentSoft, lineWidth: 1))
                    }
                }
            }
        }
    }

    private func sendButton(size: CGFloat, radius: CGFloat, iconSize: CGFloat) -> some View {
        Button {
            if session.isGenerating {
                session.stop()
            } else {
                session.send()
            }
        } label: {
            Image(systemName: session.isGenerating ? "stop.fill" : "arrow.up")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(session.isGenerating || session.canSend ? .white : Theme.Colors.sendDisabledForeground)
                .frame(width: size, height: size)
                .background(
                    session.isGenerating ? Theme.Colors.ink : (session.canSend ? Theme.Colors.accent : Theme.Colors.sendDisabledBackground),
                    in: RoundedRectangle(cornerRadius: radius, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(!session.isGenerating && !session.canSend)
        .accessibilityLabel(session.isGenerating ? "Stop" : "Send")
        .accessibilityIdentifier("composer.send")
    }
}
