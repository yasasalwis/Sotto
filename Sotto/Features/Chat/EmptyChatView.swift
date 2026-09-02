import SwiftData
import SwiftUI

struct ChatSuggestion: Identifiable {
    enum Action {
        case prefill(text: String, personaName: String?)
        case attach
        case compare
    }

    let id = UUID()
    var title: String
    var subtitle: String
    var action: Action
}

struct EmptyChatView: View {
    @Bindable var session: ChatSession
    @Environment(AppServices.self) private var services
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \Persona.sortOrder) private var personas: [Persona]

    private var suggestions: [ChatSuggestion] {
        let modelLabel = session.modelDescriptor?.shortLabel ?? "apple on-device"
        #if os(macOS)
        return [
            ChatSuggestion(title: "Tighten this paragraph", subtitle: "Editor persona · \(modelLabel)", action: .prefill(text: "Tighten this paragraph without changing its meaning:\n\n", personaName: "Editor")),
            ChatSuggestion(title: "Explain this shell command", subtitle: "Terse answers · \(modelLabel)", action: .prefill(text: "Explain this shell command flag by flag:\n\n", personaName: "Shell helper")),
            ChatSuggestion(title: "Summarize a dropped file", subtitle: "Stays on disk · \(modelLabel)", action: .attach),
            ChatSuggestion(title: "Draft a reply, three tones", subtitle: "Compare mode · 2 models", action: .compare),
        ]
        #else
        return [
            ChatSuggestion(title: "Tighten this paragraph", subtitle: "Editor persona", action: .prefill(text: "Tighten this paragraph without changing its meaning:\n\n", personaName: "Editor")),
            ChatSuggestion(title: "Summarize what I paste", subtitle: "Stays on the device", action: .prefill(text: "Summarize this in five bullet points:\n\n", personaName: nil)),
            ChatSuggestion(title: "Draft a reply, three tones", subtitle: "Compare two models", action: .compare),
        ]
        #endif
    }

    var body: some View {
        VStack(spacing: 34) {
            VStack(spacing: 12) {
                Text("What are we working on?")
                    .font(Theme.Fonts.sans(26, weight: .regular))
                    .tracking(-0.7)
                    .foregroundStyle(Theme.Colors.ink)
                MonoText(statusLine, size: 12, color: Theme.Colors.accent)
            }
            suggestionGrid
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { AppleIntelligenceEngine.prewarm() }
    }

    private var statusLine: String {
        if session.modelDescriptor?.isAvailable == false, let reason = session.modelDescriptor?.unavailableReason {
            return reason
        }
        #if os(macOS)
        return "Running locally · no network"
        #else
        return "on-device · no network"
        #endif
    }

    @ViewBuilder
    private var suggestionGrid: some View {
        #if os(macOS)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(suggestions) { suggestion in
                card(suggestion)
            }
        }
        .frame(maxWidth: 660)
        #else
        VStack(spacing: 9) {
            ForEach(suggestions) { suggestion in
                card(suggestion)
            }
        }
        #endif
    }

    private func card(_ suggestion: ChatSuggestion) -> some View {
        Button {
            perform(suggestion)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(suggestion.title)
                    .font(Theme.Fonts.sans(14, weight: .medium))
                    .foregroundStyle(Theme.Colors.ink)
                Text(suggestion.subtitle)
                    .font(Theme.Fonts.sans(13))
                    .foregroundStyle(Theme.Colors.hint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .card(radius: Theme.Radius.card)
        }
        .buttonStyle(PlainRowButtonStyle())
        .accessibilityIdentifier("chat.suggestion")
    }

    private func perform(_ suggestion: ChatSuggestion) {
        switch suggestion.action {
        case .prefill(let text, let personaName):
            if let personaName, let persona = personas.first(where: { $0.name == personaName }) {
                session.setPersona(persona)
            }
            session.draft = text
        case .attach:
            services.state.isAttachingFile = true
        case .compare:
            services.state.comparePrompt = "Draft a reply to this message in three tones: warm, neutral, and firm.\n\n"
            services.state.compareModelRefs = [session.conversation.modelRef]
            #if os(macOS)
            openWindow(id: WindowID.compare)
            #else
            services.state.sheet = .compare
            #endif
        }
    }
}
