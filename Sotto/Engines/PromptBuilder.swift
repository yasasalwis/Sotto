import Foundation

/// Turns stored messages into a `GenerationRequest` that fits the model's context window,
/// dropping the oldest turns first and never dropping the newest user message.
enum PromptBuilder {
    struct Result: Hashable, Sendable {
        var request: GenerationRequest
        var droppedTurns: Int
        var estimatedPromptTokens: Int
    }

    static let templateOverheadTokens = 48
    static let perTurnOverheadTokens = 6

    static func turns(from messages: [Message], upTo boundary: Message? = nil) -> [ChatTurn] {
        var turns: [ChatTurn] = []
        for message in messages {
            if let boundary, message.id == boundary.id { break }
            switch message.role {
            case .user:
                turns.append(ChatTurn(role: .user, content: message.promptText))
            case .assistant:
                let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard message.state != .failed, !text.isEmpty else { continue }
                turns.append(ChatTurn(role: .assistant, content: message.text))
            case .system:
                continue
            }
        }
        // Merge consecutive user turns so templates always alternate.
        var merged: [ChatTurn] = []
        for turn in turns {
            if let last = merged.last, last.role == turn.role, turn.role == .user {
                merged[merged.count - 1].content += "\n\n" + turn.content
            } else {
                merged.append(turn)
            }
        }
        return merged
    }

    static func build(
        turns: [ChatTurn],
        systemPrompt: String?,
        sampling: SamplingSettings,
        contextLength: Int,
        seed: UInt32? = nil,
        countTokens: (String) async throws -> Int
    ) async throws -> Result {
        guard let lastUser = turns.last, lastUser.role == .user else {
            throw EngineError.noUserMessage
        }
        let responseReserve = min(sampling.maxTokens, max(contextLength / 4, 128))
        let budget = contextLength - responseReserve - templateOverheadTokens
        let systemTokens = try await countTokens(systemPrompt ?? "")
        var costs: [Int] = []
        for turn in turns {
            costs.append(try await countTokens(turn.content) + perTurnOverheadTokens)
        }
        var total = systemTokens + costs.reduce(0, +)
        var dropIndex = 0
        while total > budget, dropIndex < turns.count - 1 {
            total -= costs[dropIndex]
            dropIndex += 1
        }
        if total > budget {
            throw EngineError.promptTooLong(tokens: total, limit: contextLength)
        }
        let kept = Array(turns[dropIndex...])
        let request = GenerationRequest(systemPrompt: systemPrompt, turns: kept, sampling: sampling, seed: seed)
        return Result(request: request, droppedTurns: dropIndex, estimatedPromptTokens: total)
    }
}
