import Foundation

/// The decisions behind the menu bar item, kept out of the view so they can be tested
/// without a status item on screen.
enum MenuBarModel {
    /// How many chats the menu lists. Enough to recognise this week's work, short enough
    /// that the popover stays a glance rather than a window.
    static let recentLimit = 5

    /// The prompt to send, or `nil` when the field holds nothing but whitespace.
    static func prompt(from draft: String) -> String? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The most recently active chats, newest first.
    static func recents(_ conversations: [Conversation], limit: Int = recentLimit) -> [Conversation] {
        Array(conversations.sorted { $0.lastActivity > $1.lastActivity }.prefix(limit))
    }

    /// Whether a prompt from the menu bar needs a chat of its own. An empty chat that is
    /// already open is reused, so the menu bar does not leave a trail of blank conversations.
    static func needsNewConversation(current: Conversation?) -> Bool {
        current?.isEmpty != true
    }

    /// The word after the model name in the status line under the field.
    static func statusDetail(state: ModelRuntime.LoadState, isGenerating: Bool) -> String {
        isGenerating ? "answering" : state.label
    }
}
