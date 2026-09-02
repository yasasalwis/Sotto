import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The main window: sidebar, chat and (on macOS) the inspector.
struct MainView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var context
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var compactColumn = NavigationSplitViewColumn.detail
    @State private var session: ChatSession?

    var body: some View {
        @Bindable var settings = services.settings
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $compactColumn) {
            SidebarView(compactColumn: $compactColumn)
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 200, ideal: Theme.Layout.sidebarWidth, max: 340)
                #endif
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        #if os(macOS)
        .inspector(isPresented: $settings.inspectorVisible) {
            Group {
                if let session {
                    InspectorView(session: session)
                } else {
                    InspectorView(session: nil)
                }
            }
            .inspectorColumnWidth(min: 240, ideal: Theme.Layout.inspectorWidth, max: 360)
        }
        #endif
        .task(id: services.state.selectedConversationID) {
            refreshSession()
        }
        .onChange(of: conversations.count) { _, _ in
            ensureSelection()
        }
        .onAppear {
            ensureSelection()
        }
        .sheet(item: sheetBinding) { sheet in
            sheetContent(sheet)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let session {
            ChatView(session: session, compactColumn: $compactColumn)
                .id(session.conversation.id)
        } else {
            VStack(spacing: 12) {
                Text("No conversation selected")
                    .font(Theme.Fonts.sans(15))
                    .foregroundStyle(Theme.Colors.hint)
                Button("New chat") { services.state.newChatRequests += 1 }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Colors.surface)
        }
    }

    private var sheetBinding: Binding<AppState.Sheet?> {
        Binding(get: { services.state.sheet }, set: { services.state.sheet = $0 })
    }

    @ViewBuilder
    private func sheetContent(_ sheet: AppState.Sheet) -> some View {
        switch sheet {
        case .modelPicker:
            if let session {
                ModelPickerSheet(session: session)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.hidden)
            }
        case .personaPicker:
            if let session {
                PersonaPickerSheet(session: session)
                    .presentationDetents([.medium, .large])
            }
        case .library:
            NavigationStack { ModelLibraryView() }
        case .compare:
            NavigationStack { CompareView() }
        case .personas:
            NavigationStack { PersonasView() }
        case .tools:
            NavigationStack { ToolsView() }
        case .settings:
            NavigationStack { SettingsView() }
        case .onboarding:
            OnboardingView()
        }
    }

    private func refreshSession() {
        guard let id = services.state.selectedConversationID,
              let conversation = conversations.first(where: { $0.id == id }) else {
            session = nil
            return
        }
        if session?.conversation.id != conversation.id {
            session?.stop()
            session = ChatSession(conversation: conversation, services: services, context: context)
        }
    }

    private func ensureSelection() {
        if let id = services.state.selectedConversationID, conversations.contains(where: { $0.id == id }) {
            return
        }
        if let first = conversations.first {
            services.state.selectedConversationID = first.id
        } else {
            services.state.newChatRequests += 1
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier("public.file-url") }) else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            var url: URL?
            if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
            if let direct = item as? URL { url = direct }
            guard let url else { return }
            Task { @MainActor in
                if url.pathExtension.lowercased() == "gguf" {
                    do {
                        _ = try await services.store.importModel(from: url, into: context)
                    } catch {
                        services.state.showError("Import failed", error.localizedDescription)
                    }
                } else {
                    session?.attach(url)
                }
            }
        }
        return true
    }
}
