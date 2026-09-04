import Foundation

/// Keeps what a conversation said after its oldest turns stop fitting the context window.
///
/// `PromptBuilder` trims from the front when the history outgrows the window, and until now those
/// turns were simply gone — on Apple's fixed 4,096-token window that happens within a few
/// exchanges, and the model would contradict something it had been told minutes earlier. A digest
/// is far smaller than the turns it replaces, so it survives many more trims than the transcript
/// does.
///
/// It is rebuilt *after* a turn that had to drop something, never before one. A reply is never made
/// to wait on a summary, and conversations that fit the window pay nothing at all.
enum ConversationMemory {
    /// Longest digest worth keeping. Past this it stops being cheaper than the turns it stands in
    /// for, so the model is asked to fold old detail down rather than append forever.
    static let maximumCharacters = 1200

    /// How much of the window a digest may take before it is considered too long.
    static let digestResponseTokens = 320

    /// The persona's prompt with the digest in front of it.
    ///
    /// The digest leads because it is context the model needs before it reads the instruction, and
    /// it is labelled so the model treats it as a record of what happened rather than as something
    /// the user just said.
    static func systemPrompt(base: String?, digest: String) -> String? {
        let trimmedDigest = digest.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBase = base?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedDigest.isEmpty else { return base }
        let section = "# Earlier in this conversation\n\nThis is a summary of turns that no longer fit the context window. Treat it as established fact, and do not mention that a summary exists.\n\n\(trimmedDigest)"
        return trimmedBase.isEmpty ? section : section + "\n\n" + trimmedBase
    }

    /// The instruction that produces the next digest.
    ///
    /// It asks for the things a later turn actually needs — decisions, names, constraints — rather
    /// than a précis of the prose, because a summary that reads well but loses the one filename the
    /// user mentioned is worse than useless.
    static func digestPrompt(previous: String, turns: [ChatTurn]) -> String {
        var text = "Summarise this conversation so it can be continued after the original turns are gone.\n\n"
        text += "Keep: decisions made, facts the user gave about themselves or their work, names, numbers, files, and anything the user asked for that is not finished. Drop: pleasantries, restatements, and your own explanations that led nowhere. Write it as short factual notes, not as a story, and never invent anything that is not below.\n\n"
        text += "Answer with the summary only, under \(maximumCharacters) characters.\n\n"
        if !previous.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text += "## Summary so far\n\n\(previous)\n\n"
        }
        text += "## Turns to fold in\n\n"
        text += transcript(of: turns)
        return text
    }

    static func transcript(of turns: [ChatTurn]) -> String {
        turns.map { turn in
            let speaker: String
            switch turn.role {
            case .user: speaker = "User"
            case .assistant: speaker = "Assistant"
            case .system: speaker = "System"
            }
            return "\(speaker): \(turn.content)"
        }
        .joined(separator: "\n\n")
    }

    /// Trims a model's answer down to something worth storing.
    ///
    /// A small model will sometimes preface a summary with "Here is the summary:" or wrap it in a
    /// code fence; both are stripped so the digest reads as notes rather than as an answer.
    static func clean(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        result = result.replacingOccurrences(of: "```markdown", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["Here is the summary:", "Here's the summary:", "Summary:", "Here is a summary:"] {
            if result.lowercased().hasPrefix(prefix.lowercased()) {
                result = String(result.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        guard result.count > maximumCharacters else { return result }
        // Cut at a line boundary so the digest never ends mid-note.
        let cut = result.prefix(maximumCharacters)
        if let lastBreak = cut.lastIndex(of: "\n") {
            return String(cut[..<lastBreak]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(cut).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
