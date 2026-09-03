import Foundation
import SwiftData
import Testing
@testable import Sotto

/// The menu bar item's decisions: what counts as a prompt, which chats it lists, and what the
/// status line says. The view itself is macOS-only; `MenuBarModel` is not, so these run on
/// both platforms.
@MainActor
struct MenuBarModelTests {
    @Test func whitespaceOnlyDraftsAreNotPrompts() {
        #expect(MenuBarModel.prompt(from: "") == nil)
        #expect(MenuBarModel.prompt(from: "   \n\t ") == nil)
        #expect(MenuBarModel.prompt(from: "  summarise this  ") == "summarise this")
    }

    @Test func recentsAreNewestFirstAndCapped() {
        let now = Date()
        let conversations = (0..<8).map { index -> Conversation in
            let conversation = Conversation(modelRef: .apple)
            conversation.title = "chat \(index)"
            conversation.updatedAt = now.addingTimeInterval(Double(index))
            return conversation
        }
        let recents = MenuBarModel.recents(conversations.shuffled())
        #expect(recents.count == MenuBarModel.recentLimit)
        #expect(recents.map(\.title) == ["chat 7", "chat 6", "chat 5", "chat 4", "chat 3"])
    }

    @Test func recentsHandleFewerChatsThanTheLimit() {
        let conversation = Conversation(modelRef: .apple)
        #expect(MenuBarModel.recents([]).isEmpty)
        #expect(MenuBarModel.recents([conversation]).count == 1)
    }

    @Test func statusDetailPrefersWhatTheRuntimeIsDoing() {
        #expect(MenuBarModel.statusDetail(state: .idle, isGenerating: false) == "idle")
        #expect(MenuBarModel.statusDetail(state: .loaded(name: "qwen"), isGenerating: false) == "loaded")
        #expect(MenuBarModel.statusDetail(state: .failed("no memory"), isGenerating: false) == "failed")
        // Generating outranks the load state, which is still "loaded" mid-answer.
        #expect(MenuBarModel.statusDetail(state: .loaded(name: "qwen"), isGenerating: true) == "answering")
    }

    @Test func menuBarIsOnByDefaultAndSurvivesAReset() {
        let suite = UserDefaults(suiteName: "menu-bar-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: suite)
        #expect(store.showMenuBarExtra == true)
        store.showMenuBarExtra = false
        #expect(SettingsStore(defaults: suite).showMenuBarExtra == false)
        store.resetToDefaults()
        #expect(store.showMenuBarExtra == true)
    }
}

/// Where a prompt typed in the menu bar lands. `AppServices` itself is not built here: it
/// opens a background `URLSession` with a fixed identifier, so a second instance in one
/// process wedges the test host.
@MainActor
struct QuickPromptTests {
    @Test func aPromptNeedsAChatWhenNoneIsOpen() {
        #expect(MenuBarModel.needsNewConversation(current: nil) == true)
    }

    @Test func aPromptReusesTheEmptyChatThatIsAlreadyOpen() {
        let empty = Conversation(modelRef: .apple)
        #expect(MenuBarModel.needsNewConversation(current: empty) == false)
    }

    @Test func aPromptNeverLandsInAChatThatHasMessages() {
        let used = Conversation(modelRef: .apple)
        used.messages.append(Message(role: .user, text: "earlier question"))
        #expect(MenuBarModel.needsNewConversation(current: used) == true)
    }
}
