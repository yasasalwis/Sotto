import SwiftData
import SwiftUI
import os
import UniformTypeIdentifiers

/// Chooses onboarding, the lock screen, or the main window, and reacts to menu-driven requests.
struct RootView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif
    @Query(sort: \InstalledModel.importedAt, order: .reverse) private var installed: [InstalledModel]
    @Query(sort: \Persona.sortOrder) private var personas: [Persona]

    var body: some View {
        @Bindable var state = services.state
        Group {
            if !services.settings.hasCompletedOnboarding {
                OnboardingView()
            } else {
                MainView()
            }
        }
        .overlay {
            if services.lock.status != .unlocked {
                AppLockView()
                    .transition(.opacity)
            }
        }
        .background(Theme.Colors.surface)
        .alert(item: $state.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
        .onChange(of: services.state.newChatRequests) { _, _ in
            createConversation()
        }
        .onChange(of: services.state.requestedPersonaSlot) { _, slot in
            guard let slot else { return }
            services.state.requestedPersonaSlot = nil
            applyPersona(slot: slot)
        }
        .onChange(of: scenePhase) { _, phase in
            handleScenePhase(phase)
        }
        .task {
            if services.persistenceFailure != nil {
                services.state.showError("Conversations aren't being saved", "Sotto couldn't open its database, so this session is in memory only. Quit and relaunch; if it keeps happening, use Settings › Advanced › Reset.")
            }
            await services.refreshCatalogIfDue()
        }
        .fileImporter(isPresented: $state.isImportingModel, allowedContentTypes: [.gguf, .data], allowsMultipleSelection: false) { result in
            handleImport(result)
        }
        .onOpenURL { url in
            handleOpenURL(url)
        }
    }

    /// Creates a new chat with the default model and persona and selects it.
    func createConversation() {
        let ref = ModelRegistry.preferredDefault(installed: installed, settings: services.settings)
        let conversation = Conversation(modelRef: ref, personaID: services.settings.defaultPersonaID)
        context.insert(conversation)
        try? context.save()
        services.state.selectedConversationID = conversation.id
        Log.chat.info("Created conversation")
    }

    private func applyPersona(slot: Int) {
        guard let persona = personas.first(where: { $0.shortcutSlot == slot }) else { return }
        guard let id = services.state.selectedConversationID,
              let conversation = try? context.fetch(FetchDescriptor<Conversation>(predicate: #Predicate { $0.id == id })).first else {
            services.settings.defaultPersonaID = persona.id
            return
        }
        conversation.personaID = persona.id
        if let ref = persona.modelRef {
            conversation.modelRef = ref
        }
        try? context.save()
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            if services.settings.requireAppLock, AppLock.isAvailable {
                services.lock.lock()
            }
        case .active:
            if services.lock.status == .locked, !services.lock.isPrompting {
                Task { await services.lock.unlock() }
            }
        default:
            break
        }
    }

    /// Handles `.gguf` files (Finder double-click, "Open in Sotto" from Files) and the `sotto://`
    /// scheme used by Shortcuts and the command line: `sotto://new`, `sotto://library`,
    /// `sotto://compare`, `sotto://personas`, `sotto://settings`.
    private func handleOpenURL(_ url: URL) {
        if url.isFileURL {
            guard url.pathExtension.lowercased() == "gguf" else { return }
            handleImport(.success([url]))
            return
        }
        guard url.scheme?.lowercased() == "sotto" else { return }
        switch url.host?.lowercased() {
        case "new":
            services.state.newChatRequests += 1
        case "library":
            openWindowOrSheet(id: WindowID.library, sheet: .library)
        case "compare":
            openWindowOrSheet(id: WindowID.compare, sheet: .compare)
        case "personas":
            openWindowOrSheet(id: WindowID.personas, sheet: .personas)
        case "tools":
            openWindowOrSheet(id: WindowID.tools, sheet: .tools)
        case "settings":
            #if os(macOS)
            openSettings()
            #else
            services.state.sheet = .settings
            #endif
        default:
            Log.app.notice("Ignored unknown sotto:// link")
        }
    }

    private func openWindowOrSheet(id: String, sheet: AppState.Sheet) {
        #if os(macOS)
        openWindow(id: id)
        #else
        services.state.sheet = sheet
        #endif
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                do {
                    _ = try await services.store.importModel(from: url, into: context)
                } catch {
                    services.state.showError("Import failed", error.localizedDescription)
                }
            }
        case .failure(let error):
            services.state.showError("Import failed", error.localizedDescription)
        }
    }
}

struct AppLockView: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        VStack(spacing: 18) {
            LogoMark(size: 52, radius: 15)
            Text("Sotto is locked")
                .font(Theme.Fonts.sans(22, weight: .medium))
                .foregroundStyle(Theme.Colors.ink)
            if case .failed(let message) = services.lock.status {
                Text(message)
                    .font(Theme.Fonts.sans(13))
                    .foregroundStyle(Theme.Colors.hint)
                    .multilineTextAlignment(.center)
            }
            Button("Unlock with \(AppLock.biometryLabel)") {
                Task { await services.lock.unlock() }
            }
            .buttonStyle(PrimaryButtonStyle(size: 15, horizontalPadding: 24, verticalPadding: 12, radius: 9))
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.surface)
    }
}
