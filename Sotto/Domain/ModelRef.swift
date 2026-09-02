import Foundation

/// Identifies which model a conversation, persona or message uses.
enum ModelRef: Hashable, Sendable, Codable {
    case apple
    case gguf(UUID)

    static let ggufPrefix = "gguf:"

    init?(rawValue: String) {
        if rawValue == "apple" {
            self = .apple
        } else if rawValue.hasPrefix(Self.ggufPrefix), let id = UUID(uuidString: String(rawValue.dropFirst(Self.ggufPrefix.count))) {
            self = .gguf(id)
        } else {
            return nil
        }
    }

    var rawValue: String {
        switch self {
        case .apple: return "apple"
        case .gguf(let id): return Self.ggufPrefix + id.uuidString
        }
    }

    var isApple: Bool {
        if case .apple = self { return true }
        return false
    }

    var ggufID: UUID? {
        if case .gguf(let id) = self { return id }
        return nil
    }
}
