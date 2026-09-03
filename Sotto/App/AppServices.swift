import Foundation
import Observation
import SwiftData
import os

/// Everything long-lived the UI needs, built once at launch and injected through the environment.
@Observable
final class AppServices {
    let settings: SettingsStore
    let store: ModelStore
    let container: ModelContainer
    let runtime: ModelRuntime
    let downloads: DownloadManager
    let diagnostics: DiagnosticsCollector
    let lock: AppLock
    let catalog: ModelCatalog
    let state: AppState
    /// Set when the on-disk store could not be opened and an in-memory store is in use instead.
    let persistenceFailure: String?

    init() {
        let settings = SettingsStore()
        let store = ModelStore()
        let catalog = (try? ModelCatalog.loadBundled()) ?? ModelCatalog(version: 0, updatedAt: "", entries: [])
        var failure: String?
        let container: ModelContainer
        do {
            container = try PersistenceController.makeContainer(inMemory: !settings.storeConversations, baseDirectory: store.baseDirectory)
        } catch {
            Log.persistence.error("Opening the store failed: \(error.localizedDescription, privacy: .public)")
            failure = error.localizedDescription
            container = try! PersistenceController.makeContainer(inMemory: true, baseDirectory: store.baseDirectory)
        }
        PersistenceController.seedIfNeeded(context: container.mainContext)

        self.settings = settings
        self.store = store
        self.container = container
        self.catalog = catalog
        self.persistenceFailure = failure
        self.runtime = ModelRuntime(store: store, settings: settings)
        self.downloads = DownloadManager(store: store, settings: settings, container: container, catalog: catalog)
        self.diagnostics = DiagnosticsCollector(directory: store.diagnosticsDirectory)
        self.lock = AppLock()
        self.state = AppState()

        diagnostics.setEnabled(settings.crashReports)
        if settings.requireAppLock, AppLock.isAvailable {
            lock.lock()
        }
        reconcileLibrary()
        reconcileInterruptedMessages()
        Log.app.info("Sotto started; persistence=\(settings.storeConversations ? "disk" : "memory", privacy: .public)")
    }

    /// Creates a chat with the default model and persona and selects it. Lives here rather
    /// than in a view because ⌘N and the menu bar both need it, and the menu bar may fire it
    /// while no window exists.
    @MainActor
    @discardableResult
    func startConversation() -> Conversation {
        let context = container.mainContext
        let installed = (try? context.fetch(FetchDescriptor<InstalledModel>())) ?? []
        let ref = ModelRegistry.preferredDefault(installed: installed, settings: settings)
        let conversation = Conversation(modelRef: ref, personaID: settings.defaultPersonaID)
        context.insert(conversation)
        try? context.save()
        state.selectedConversationID = conversation.id
        Log.chat.info("Created conversation")
        return conversation
    }

    /// Prepares a chat for a prompt typed into the menu bar and stores the prompt for
    /// `MainView` to send once its session exists. The chat is created here so the prompt
    /// survives the window being closed; an empty chat that is already open is reused rather
    /// than leaving a stray one behind.
    @MainActor
    func startQuickPrompt(_ prompt: String) {
        let context = container.mainContext
        let current = state.selectedConversationID.flatMap { id in
            try? context.fetch(FetchDescriptor<Conversation>(predicate: #Predicate { $0.id == id })).first
        }
        if MenuBarModel.needsNewConversation(current: current) {
            startConversation()
        }
        state.quickPrompt = prompt
        Log.chat.info("Queued a prompt from the menu bar")
    }

    /// Drops records whose files vanished and orphaned files nothing references.
    func reconcileLibrary() {
        let context = container.mainContext
        guard let records = try? context.fetch(FetchDescriptor<InstalledModel>()) else { return }
        let missing = store.reconcile(records: records)
        for record in missing {
            Log.models.notice("Model file missing for \(record.name, privacy: .public); removing record")
            context.delete(record)
        }
        if !missing.isEmpty { try? context.save() }
    }

    /// A message still marked as streaming means the app quit mid-reply. Mark it stopped so it
    /// does not sit in the transcript looking like an empty answer forever.
    func reconcileInterruptedMessages() {
        let context = container.mainContext
        let streaming = MessageState.streaming.rawValue
        let descriptor = FetchDescriptor<Message>(predicate: #Predicate { $0.stateRaw == streaming })
        guard let interrupted = try? context.fetch(descriptor), !interrupted.isEmpty else { return }
        for message in interrupted {
            message.state = .cancelled
            if message.text.isEmpty {
                message.errorMessage = "Sotto quit before this answer arrived."
            }
        }
        try? context.save()
        Log.chat.notice("Marked \(interrupted.count) interrupted message(s) as stopped")
    }

    func refreshCatalogIfDue() async {
        guard CatalogRefresher.isDue(settings: settings) else { return }
        _ = await CatalogRefresher.refresh(catalog: catalog, settings: settings)
    }

    /// "Erase all data": conversations, personas (re-seeded), models, downloads, diagnostics and preferences.
    func eraseEverything() throws {
        Task { await runtime.unload() }
        let context = container.mainContext
        if let downloads = try? context.fetch(FetchDescriptor<ModelDownload>()) {
            for download in downloads { self.downloads.cancel(download) }
        }
        try PersistenceController.eraseAll(context: context)
        try store.eraseEverything()
        KeychainStore.removeAll()
        diagnostics.deleteAllReports()
        settings.resetToDefaults()
        settings.hasCompletedOnboarding = false
        PersistenceController.seedIfNeeded(context: context)
        state.selectedConversationID = nil
        Log.privacy.notice("All local data erased by user")
    }
}
