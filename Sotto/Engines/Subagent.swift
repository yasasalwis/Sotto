import Foundation

/// Hands one self-contained task to a fresh model session and returns only its answer.
///
/// The point is the window, not the cleverness. Every session gets its own context — Apple's is a
/// fixed 4,096 tokens — so a chat that has spent most of its room on history and tool definitions
/// can still give a subagent a clean one. The parent pays for the task it wrote and the answer it
/// got back, not for the working-out in between.
///
/// It is deliberately one shot: no tools, no conversation, no nesting. A subagent that could call a
/// subagent is a way to spend a whole battery on a question nobody asked, and a subagent that could
/// call tools would need its own approval flow. Neither is worth it for the value this adds.
enum Subagent {
    /// What the subagent is told before the task.
    static let instructions = "You handle one self-contained task and return only its result. Do not greet, do not explain your working, and do not ask questions — you cannot receive an answer. If the task cannot be done with what you were given, say so in one sentence."

    /// Longest task worth accepting. Past this the parent is pasting its context in rather than
    /// delegating, which defeats the point.
    static let maximumTaskCharacters = 2000

    /// Room the subagent gets for its answer. Small on purpose: the result is going straight back
    /// into the parent's window, which is the resource under pressure.
    static let responseTokens = 512

    static func run(task: String, engine: InferenceEngine) async throws -> String {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ToolExecutionError.invalidArguments("“task” is required and must describe one job")
        }
        guard trimmed.count <= maximumTaskCharacters else {
            throw ToolExecutionError.invalidArguments("“task” is longer than \(Format.integer(maximumTaskCharacters)) characters. Give the subagent one job, not the whole conversation")
        }

        var sampling = SamplingSettings.default
        sampling.maxTokens = responseTokens
        let request = GenerationRequest(
            systemPrompt: instructions,
            turns: [ChatTurn(role: .user, content: trimmed)],
            sampling: sampling,
            seed: nil
        )

        var text = ""
        // No tool runner: a subagent runs on what it knows.
        for try await event in engine.generate(request) {
            switch event {
            case .delta(let delta): text += delta
            case .replace(let whole): text = whole
            default: break
            }
        }

        let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else {
            return "The subagent returned nothing. Answer the task yourself."
        }
        return answer
    }
}
