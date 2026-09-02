import Foundation

/// Cheap token estimate used for the composer counter and for models whose tokenizer we
/// cannot run locally (Apple's system model). Calibrated to roughly 4 characters per token
/// for English prose, with a floor of one token per whitespace-separated word.
enum TokenEstimator {
    static func estimate(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let characters = text.count
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        return max(words, Int((Double(characters) / 4).rounded(.up)))
    }
}
