import Foundation
import Observation

/// Transient UI state shared across windows: selection, sheets, alerts and menu-driven requests.
@Observable
final class AppState {
    enum Sheet: Identifiable, Hashable {
        case modelPicker
        case personaPicker
        case library
        case compare
        case personas
        case tools
        case settings
        case onboarding

        var id: Self { self }
    }

    struct AlertContent: Identifiable, Hashable {
        var id = UUID()
        var title: String
        var message: String
    }

    var selectedConversationID: UUID?
    var sheet: Sheet?
    var alert: AlertContent?
    /// Incremented by the ⌘N menu command; the root view observes it and creates a chat.
    var newChatRequests = 0
    /// Persona slot requested by ⌥⌘1…9.
    var requestedPersonaSlot: Int?
    /// A prompt typed into the menu bar, waiting for a chat session to send it.
    var quickPrompt: String?
    /// Prompt to prefill when the compare window opens.
    var comparePrompt: String?
    var compareModelRefs: [ModelRef] = []
    /// Persona to open in the presets window.
    var personaToEdit: UUID?
    var toolToEdit: UUID?
    var isImportingModel = false
    var isAttachingFile = false
    var showModelLibraryImport = false

    func showError(_ title: String, _ message: String) {
        alert = AlertContent(title: title, message: message)
    }
}
