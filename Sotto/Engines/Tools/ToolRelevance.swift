import Foundation

/// A last check, in code, on whether a tool the model asked for has any business running.
///
/// Two rounds of prompt work did not stop this. The tool descriptions say "Do not call it for
/// general knowledge", the shared restraint rule says most messages need no tool, and the
/// dispatcher's preamble says general-knowledge questions are never a reason to call one. A 3B
/// model still answered "What is a large language model?" by searching the person's own chats for
/// "large language model" — twice, in two different builds.
///
/// So the rule is enforced rather than requested. This is deliberately narrow: it covers the one
/// tool that keeps misfiring, where the test is unambiguous, and leaves every other tool to the
/// model's judgement. A guard that tried to second-guess the calculator would do more harm than
/// the misfires it prevented — "what is 17 × 23" is a general-knowledge question in form and a
/// perfectly good reason to reach for arithmetic.
enum ToolRelevance {
    /// Words that mean the person is pointing at their own past rather than at the world.
    ///
    /// Whole words only: "we" must not match "week", and "us" must not match "because".
    static let historyMarkers: Set<String> = [
        "my", "mine", "our", "ours", "we", "us",
        "earlier", "previously", "remember", "recall",
        "discussed", "mentioned", "told", "said",
        "chat", "chats", "conversation", "conversations", "talked",
        "yesterday", "ago",
    ]

    /// Phrases that carry the same meaning but only as a pair of words.
    static let historyPhrases = ["last week", "last time", "last night", "before that", "back then"]

    static func referencesOwnHistory(_ text: String) -> Bool {
        let lowered = text.lowercased()
        if historyPhrases.contains(where: { lowered.contains($0) }) { return true }
        let words = lowered.split(whereSeparator: { !$0.isLetter })
        return words.contains { historyMarkers.contains(String($0)) }
    }

    /// Whether this tool may run for the message that prompted it.
    ///
    /// Everything except the chat search is allowed through: the model is better placed than a word
    /// list to know when a converter or a hash is wanted.
    static func allows(_ builtIn: BuiltInToolID?, forUserMessage message: String) -> Bool {
        guard builtIn == .searchConversations else { return true }
        // This judges a message; with no message there is nothing to judge, so it does not block.
        // Only reachable outside a turn — the tool editor's "Run once", or a harness.
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        return referencesOwnHistory(message)
    }

    /// What the model is told when a call is refused, phrased so it answers rather than retries.
    static let refusal = "Not run: this question is not about the user's earlier conversations. Answer it directly from what you know, and do not call this tool again for this message."
}
