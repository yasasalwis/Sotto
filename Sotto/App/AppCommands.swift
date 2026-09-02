import SwiftUI

struct AppCommands: Commands {
    let services: AppServices
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Chat") {
                services.state.newChatRequests += 1
            }
            .keyboardShortcut("n", modifiers: .command)
        }
        CommandMenu("Models") {
            Button("Model Library…") { openLibrary() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Button("Compare Models…") { openCompare() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            Button("Presets & Personas…") { openPersonas() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Divider()
            Button("Import GGUF…") {
                services.state.isImportingModel = true
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            Divider()
            Button("Unload Model") {
                Task { await services.runtime.unload() }
            }
            .disabled(services.runtime.loadedModel == nil)
        }
        CommandMenu("Persona") {
            ForEach(1...9, id: \.self) { slot in
                Button("Persona \(slot)") {
                    services.state.requestedPersonaSlot = slot
                }
                .keyboardShortcut(KeyEquivalent(Character(String(slot))), modifiers: [.command, .option])
            }
        }
        CommandGroup(after: .sidebar) {
            Button(services.settings.inspectorVisible ? "Hide Inspector" : "Show Inspector") {
                services.settings.inspectorVisible.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }

    private func openLibrary() {
        #if os(macOS)
        openWindow(id: WindowID.library)
        #else
        services.state.sheet = .library
        #endif
    }

    private func openCompare() {
        #if os(macOS)
        openWindow(id: WindowID.compare)
        #else
        services.state.sheet = .compare
        #endif
    }

    private func openPersonas() {
        #if os(macOS)
        openWindow(id: WindowID.personas)
        #else
        services.state.sheet = .personas
        #endif
    }
}
