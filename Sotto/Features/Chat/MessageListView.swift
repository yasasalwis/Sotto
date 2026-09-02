import SwiftUI

struct MessageListView: View {
    @Bindable var session: ChatSession
    @Environment(AppServices.self) private var services

    private var messages: [Message] { session.conversation.orderedMessages }

    private var streamingText: String {
        guard let id = session.streamingMessageID else { return "" }
        return messages.first(where: { $0.id == id })?.text ?? ""
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: rowSpacing) {
                    if session.droppedTurns > 0 {
                        MonoText("\(session.droppedTurns) earlier turns left out to fit the context window", size: 10, color: Theme.Colors.faint)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(messages) { message in
                        MessageRow(message: message, session: session)
                            .id(message.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
            }
            .onChange(of: streamingText.count) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onAppear {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private var rowSpacing: CGFloat {
        #if os(macOS)
        return 20
        #else
        return 18
        #endif
    }

    private var horizontalPadding: CGFloat {
        #if os(macOS)
        return 44
        #else
        return 18
        #endif
    }

    private var verticalPadding: CGFloat {
        #if os(macOS)
        return 22
        #else
        return 20
        #endif
    }
}

struct MessageRow: View {
    let message: Message
    @Bindable var session: ChatSession
    @Environment(AppServices.self) private var services

    var body: some View {
        switch message.role {
        case .user:
            userBubble
        case .assistant:
            assistantBlock
        case .system:
            EmptyView()
        }
    }

    // MARK: - User

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 8) {
                if !message.attachmentNames.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(message.attachmentNames, id: \.self) { name in
                            HStack(spacing: 4) {
                                Image(systemName: "paperclip").font(.system(size: 9))
                                Text(name).font(Theme.Fonts.mono(10)).lineLimit(1)
                            }
                            .foregroundStyle(userForeground.opacity(0.85))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(userForeground.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                    }
                }
                Text(message.text)
                    .font(Theme.Fonts.sans(15))
                    .lineSpacing(userLineSpacing)
                    .foregroundStyle(userForeground)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, userHorizontalPadding)
            .padding(.vertical, userVerticalPadding)
            .background(userBackground, in: UnevenRoundedRectangle(topLeadingRadius: userRadius, bottomLeadingRadius: userRadius, bottomTrailingRadius: userTailRadius, topTrailingRadius: userRadius, style: .continuous))
            .frame(maxWidth: bubbleMaxWidth, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .contextMenu {
            Button("Copy") { Clipboard.copy(message.text) }
            Button("Delete", role: .destructive) { session.delete(message) }
        }
    }

    // MARK: - Assistant

    private var isStreaming: Bool { session.streamingMessageID == message.id }

    private var assistantBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                LogoMark(size: 20, radius: 6)
                if isStreaming, message.text.isEmpty {
                    TypingDots()
                } else {
                    MonoText(assistantCaption, size: 11, color: Theme.Colors.hint)
                }
            }
            if !message.toolCalls.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(message.toolCalls) { record in
                        ToolCallRow(record: record)
                    }
                }
                .frame(maxWidth: assistantMaxWidth, alignment: .leading)
            }
            if !message.text.isEmpty {
                MarkdownBlocksView(text: message.text, fontSize: 15, lineSpacing: assistantLineSpacing)
                    .frame(maxWidth: assistantMaxWidth, alignment: .leading)
            }
            if let error = message.errorMessage, message.state == .failed || !message.errorMessage.isNilOrEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Colors.danger)
                    Text(error)
                        .font(Theme.Fonts.sans(13))
                        .foregroundStyle(Theme.Colors.danger)
                        .textSelection(.enabled)
                }
                .padding(12)
                .frame(maxWidth: assistantMaxWidth, alignment: .leading)
                .background(Theme.Colors.surfaceWarm, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.Colors.dangerBorder, lineWidth: 1))
            }
            if message.state == .cancelled {
                MonoText("stopped", size: 10, color: Theme.Colors.faint)
            }
            if !isStreaming {
                actions
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button("Copy") { Clipboard.copy(message.text) }
            Button("Retry") { session.retry(message) }.disabled(session.isGenerating)
            Button("Delete", role: .destructive) { session.delete(message) }.disabled(session.isGenerating)
        }
    }

    private var assistantCaption: String {
        var parts: [String] = []
        parts.append(message.modelLabel ?? session.modelDescriptor?.shortLabel ?? "model")
        if let latency = message.latencySeconds {
            parts.append(Format.seconds(latency))
        }
        return parts.joined(separator: " · ")
    }

    private var actions: some View {
        let alternatives = session.alternatives(to: message)
        return HStack(spacing: 8) {
            Button("copy") { Clipboard.copy(message.text) }
                .buttonStyle(ChipButtonStyle(size: chipSize))
                .accessibilityIdentifier("message.copy")
            Button("retry") { session.retry(message) }
                .buttonStyle(ChipButtonStyle(size: chipSize))
                .disabled(session.isGenerating)
                .accessibilityIdentifier("message.retry")
            if let first = alternatives.first {
                if alternatives.count == 1 {
                    Button("try on \(tryLabel(first))") { session.tryOn(message, ref: first.ref) }
                        .buttonStyle(ChipButtonStyle(size: chipSize))
                        .disabled(session.isGenerating)
                } else {
                    Menu {
                        ForEach(alternatives) { descriptor in
                            Button(descriptor.name) { session.tryOn(message, ref: descriptor.ref) }
                        }
                    } label: {
                        Text("try on \(tryLabel(first))")
                    }
                    .buttonStyle(ChipButtonStyle(size: chipSize))
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .disabled(session.isGenerating)
                }
            }
        }
        .padding(.top, 4)
    }

    private func tryLabel(_ descriptor: ModelDescriptor) -> String {
        descriptor.kind == .apple ? "apple 3B" : descriptor.shortLabel
    }

    // MARK: - Platform metrics

    private var userForeground: Color {
        #if os(macOS)
        return Theme.Colors.ink
        #else
        return .white
        #endif
    }

    private var userBackground: Color {
        #if os(macOS)
        return Theme.Colors.surfaceMuted
        #else
        return Theme.Colors.accent
        #endif
    }

    private var userRadius: CGFloat {
        #if os(macOS)
        return 14
        #else
        return 18
        #endif
    }

    private var userTailRadius: CGFloat {
        #if os(macOS)
        return 4
        #else
        return 5
        #endif
    }

    private var userHorizontalPadding: CGFloat {
        #if os(macOS)
        return 18
        #else
        return 15
        #endif
    }

    private var userVerticalPadding: CGFloat {
        #if os(macOS)
        return 14
        #else
        return 12
        #endif
    }

    private var userLineSpacing: CGFloat {
        #if os(macOS)
        return 5
        #else
        return 4
        #endif
    }

    private var assistantLineSpacing: CGFloat {
        #if os(macOS)
        return 6
        #else
        return 5
        #endif
    }

    private var bubbleMaxWidth: CGFloat? {
        #if os(macOS)
        return 560
        #else
        return 300
        #endif
    }

    private var assistantMaxWidth: CGFloat? {
        #if os(macOS)
        return 620
        #else
        return nil
        #endif
    }

    private var chipSize: CGFloat {
        #if os(macOS)
        return 11
        #else
        return 10
        #endif
    }
}

extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        switch self {
        case .none: return true
        case .some(let value): return value.isEmpty
        }
    }
}
