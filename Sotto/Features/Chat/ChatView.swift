import SwiftData
import SwiftUI

struct ChatView: View {
    @Bindable var session: ChatSession
    @Binding var compactColumn: NavigationSplitViewColumn
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var context
    @Environment(\.openWindow) private var openWindow
    @Query private var installed: [InstalledModel]

    private var lastThroughput: Double? {
        session.conversation.orderedMessages.last(where: { $0.role == .assistant && $0.tokensPerSecond != nil })?.tokensPerSecond
    }

    var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            header
            #endif
            if session.conversation.isEmpty {
                EmptyChatView(session: session)
            } else {
                MessageListView(session: session)
            }
            ComposerView(session: session)
        }
        .background(Theme.Colors.surface)
        #if os(iOS)
        .toolbar { iosToolbar }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.Colors.surface, for: .navigationBar)
        #endif
    }

    // MARK: - macOS header

    #if os(macOS)
    private var header: some View {
        HStack(spacing: 12) {
            ModelPill(session: session, installed: installed)
            if let tps = lastThroughput {
                Text(Format.tokensPerSecond(tps))
                    .font(Theme.Fonts.mono(11))
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.Colors.accentTint, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            Spacer()
            HStack(spacing: 16) {
                Button("Compare") { openCompare() }
                Button("Presets") { openWindow(id: WindowID.personas) }
                Button(services.settings.inspectorVisible ? "Inspector" : "Inspector") {
                    services.settings.inspectorVisible.toggle()
                }
                .foregroundStyle(services.settings.inspectorVisible ? Theme.Colors.accent : Theme.Colors.hint)
                .fontWeight(services.settings.inspectorVisible ? .medium : .regular)
            }
            .buttonStyle(.plain)
            .font(Theme.Fonts.sans(13))
            .foregroundStyle(Theme.Colors.hint)
        }
        .padding(.horizontal, 22)
        .frame(height: Theme.Layout.toolbarHeight)
        .hairlineDivider()
    }
    #endif

    // MARK: - iOS toolbar

    #if os(iOS)
    @ToolbarContentBuilder
    private var iosToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                compactColumn = .sidebar
            } label: {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .accessibilityLabel("Chats")
        }
        ToolbarItem(placement: .principal) {
            if session.conversation.isEmpty {
                ModelPill(session: session, installed: installed)
            } else {
                VStack(spacing: 2) {
                    Text(session.conversation.title)
                        .font(Theme.Fonts.sans(15, weight: .medium))
                        .foregroundStyle(Theme.Colors.ink)
                        .lineLimit(1)
                    MonoText(subtitle, size: 10, color: Theme.Colors.accent)
                }
                .onTapGesture { services.state.sheet = .modelPicker }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if session.conversation.isEmpty {
                Button {
                    services.state.newChatRequests += 1
                } label: {
                    Image(systemName: "plus").foregroundStyle(Theme.Colors.textSecondary)
                }
                .accessibilityLabel("New chat")
            } else {
                Menu {
                    Button("Change model…") { services.state.sheet = .modelPicker }
                    Button("Persona…") { services.state.sheet = .personaPicker }
                    Button("Compare two models…") { openCompare() }
                    Divider()
                    Button("New chat") { services.state.newChatRequests += 1 }
                    Button("Model library") { services.state.sheet = .library }
                    Button("Personas") { services.state.sheet = .personas }
                    Button("Settings") { services.state.sheet = .settings }
                    Divider()
                    Button("Delete chat", role: .destructive) {
                        services.state.selectedConversationID = nil
                        context.delete(session.conversation)
                        try? context.save()
                    }
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(Theme.Colors.textSecondary)
                }
                .accessibilityLabel("More")
            }
        }
    }

    private var subtitle: String {
        let label = session.modelDescriptor?.shortLabel ?? "model removed"
        if let tps = lastThroughput {
            return "\(label) · \(Format.tokensPerSecond(tps, fractionDigits: 0))"
        }
        return label
    }
    #endif

    private func openCompare() {
        services.state.comparePrompt = session.conversation.orderedMessages.last(where: { $0.role == .user })?.text ?? session.draft
        services.state.compareModelRefs = [session.conversation.modelRef]
        #if os(macOS)
        openWindow(id: WindowID.compare)
        #else
        services.state.sheet = .compare
        #endif
    }
}

/// The model selector shown in the chat header: dot, name, detail, chevron.
struct ModelPill: View {
    @Bindable var session: ChatSession
    let installed: [InstalledModel]
    @Environment(AppServices.self) private var services
    @Environment(\.openWindow) private var openWindow

    private var descriptors: [ModelDescriptor] {
        ModelRegistry.all(installed: installed, runtime: services.runtime)
    }

    private var current: ModelDescriptor? {
        ModelRegistry.descriptor(for: session.conversation.modelRef, installed: installed, runtime: services.runtime)
    }

    var body: some View {
        #if os(macOS)
        Menu {
            ForEach(descriptors) { descriptor in
                Button {
                    session.setModel(descriptor.ref)
                } label: {
                    if descriptor.isAvailable {
                        Text("\(descriptor.name) · \(descriptor.detail)")
                    } else {
                        Text("\(descriptor.name) — \(descriptor.unavailableReason ?? "unavailable")")
                    }
                }
                .disabled(!descriptor.isAvailable)
            }
            Divider()
            Button("Model library…") { openWindow(id: WindowID.library) }
        } label: {
            label
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityIdentifier("chat.modelPill")
        #else
        Button {
            services.state.sheet = .modelPicker
        } label: {
            label
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chat.modelPill")
        #endif
    }

    private var label: some View {
        HStack(spacing: 8) {
            StatusDot(color: current?.isAvailable == true ? Theme.Colors.accent : Theme.Colors.hint)
            Text(current?.name ?? "Choose a model")
                .font(Theme.Fonts.sans(13, weight: .medium))
                .foregroundStyle(Theme.Colors.ink)
                .lineLimit(1)
            #if os(macOS)
            MonoText(current?.detail ?? "", size: 11, color: Theme.Colors.hint)
            #endif
            Text("▾")
                .font(.system(size: 9))
                .foregroundStyle(Theme.Colors.placeholder)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        #if os(macOS)
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).stroke(Theme.Colors.borderMedium, lineWidth: 1))
        #else
        .background(Theme.Colors.sidebar, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        #endif
        .contentShape(Rectangle())
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}
