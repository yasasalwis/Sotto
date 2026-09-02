import SwiftData
import SwiftUI

struct SidebarView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var context
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]
    @Query private var installed: [InstalledModel]
    @Binding var compactColumn: NavigationSplitViewColumn
    @State private var renaming: Conversation?
    @State private var renameText = ""

    private var grouped: [(ConversationGroup, [Conversation])] {
        let now = Date()
        var buckets: [ConversationGroup: [Conversation]] = [:]
        for conversation in conversations {
            buckets[ConversationGroup.group(for: conversation.lastActivity, relativeTo: now), default: []].append(conversation)
        }
        return ConversationGroup.allCases.compactMap { group in
            guard let items = buckets[group], !items.isEmpty else { return nil }
            return (group, items)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            Color.clear.frame(height: 42)
            #endif
            newChatButton
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(grouped, id: \.0) { group, items in
                        SectionLabel(group.rawValue)
                            .padding(.horizontal, 20)
                            .padding(.top, group == grouped.first?.0 ? 8 : 20)
                            .padding(.bottom, 8)
                        VStack(spacing: 1) {
                            ForEach(items) { conversation in
                                row(conversation)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.bottom, 12)
            }
            Spacer(minLength: 0)
            libraryRow
            #if os(iOS)
            settingsRow
            #endif
        }
        .background(Theme.Colors.sidebar)
        #if os(macOS)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.Colors.borderSidebar).frame(width: 1) }
        #endif
        .navigationTitle("Chats")
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .alert("Rename chat", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $renameText)
            Button("Save") {
                if let renaming {
                    renaming.title = String(renameText.prefix(80))
                    renaming.isTitleGenerated = true
                    try? context.save()
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private var newChatButton: some View {
        Button {
            services.state.newChatRequests += 1
            compactColumn = .detail
        } label: {
            HStack(spacing: 8) {
                Text("＋ New chat")
                    .font(Theme.Fonts.sans(13, weight: .medium))
                    .foregroundStyle(Theme.Colors.ink)
                Spacer()
                #if os(macOS)
                MonoText("⌘N", size: 11, color: Theme.Colors.placeholder)
                #endif
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .card(radius: Theme.Radius.control, border: Theme.Colors.borderMedium)
        }
        .buttonStyle(PlainRowButtonStyle())
        .accessibilityIdentifier("sidebar.newChat")
    }

    private func row(_ conversation: Conversation) -> some View {
        let selected = services.state.selectedConversationID == conversation.id
        let descriptor = ModelRegistry.descriptor(for: conversation.modelRef, installed: installed, runtime: services.runtime)
        return Button {
            services.state.selectedConversationID = conversation.id
            compactColumn = .detail
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(conversation.title)
                    .font(Theme.Fonts.sans(13, weight: selected ? .medium : .regular))
                    .foregroundStyle(selected ? Theme.Colors.ink : Theme.Colors.textSecondary)
                    .lineLimit(1)
                MonoText(descriptor?.shortLabel ?? "model removed", size: 10, color: selected ? Theme.Colors.accent : Theme.Colors.placeholder)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(selected ? Theme.Colors.accentTint : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(PlainRowButtonStyle())
        .contextMenu {
            Button("Rename…") {
                renameText = conversation.title
                renaming = conversation
            }
            Button("Delete", role: .destructive) { delete(conversation) }
        }
        .accessibilityIdentifier("sidebar.conversation")
    }

    private var libraryRow: some View {
        Button {
            #if os(macOS)
            openWindow(id: WindowID.library)
            #else
            services.state.sheet = .library
            #endif
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Theme.Colors.accentSoft)
                    .frame(width: 26, height: 26)
                    .overlay(Image(systemName: "square.grid.2x2").font(.system(size: 12)).foregroundStyle(Theme.Colors.accent))
                Text("Model library")
                    .font(Theme.Fonts.sans(13))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                MonoText("\(installed.count + (AppleIntelligenceEngine.isAvailable ? 1 : 0))", size: 10, color: Theme.Colors.placeholder)
            }
            .padding(14)
            .overlay(alignment: .top) { Rectangle().fill(Theme.Colors.borderSidebar).frame(height: 1) }
        }
        .buttonStyle(PlainRowButtonStyle())
        .accessibilityIdentifier("sidebar.library")
    }

    #if os(iOS)
    private var settingsRow: some View {
        Button {
            services.state.sheet = .settings
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Theme.Colors.surfaceMuted)
                    .frame(width: 26, height: 26)
                    .overlay(Image(systemName: "gearshape").font(.system(size: 12)).foregroundStyle(Theme.Colors.muted))
                Text("Settings")
                    .font(Theme.Fonts.sans(13))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .buttonStyle(PlainRowButtonStyle())
        .accessibilityIdentifier("sidebar.settings")
    }
    #endif

    private func delete(_ conversation: Conversation) {
        if services.state.selectedConversationID == conversation.id {
            services.state.selectedConversationID = nil
        }
        context.delete(conversation)
        try? context.save()
    }
}
