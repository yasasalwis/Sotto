import Foundation

/// Fallback prompt format used when a model ships without a chat template that
/// llama.cpp recognises. ChatML is understood by most instruction-tuned models.
enum ChatMLTemplate {
    static func render(_ messages: [LlamaChatMessage], addAssistantPrefix: Bool = true) -> String {
        var output = ""
        for message in messages {
            output += "<|im_start|>\(message.role)\n\(message.content)<|im_end|>\n"
        }
        if addAssistantPrefix {
            output += "<|im_start|>assistant\n"
        }
        return output
    }
}
