import Foundation
import SwiftData

enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

enum MessageState: String, Codable, Sendable {
    case complete
    case streaming
    case failed
    case cancelled
}

@Model
final class Message {
    @Attribute(.unique) var id: UUID
    var roleRaw: String
    var text: String
    var createdAt: Date
    var modelRefRaw: String?
    var modelLabel: String?
    var latencySeconds: Double?
    var tokensPerSecond: Double?
    var promptTokens: Int?
    var generatedTokens: Int?
    var stateRaw: String
    var errorMessage: String?
    var attachmentNames: [String]
    /// Text extracted from attachments. Sent to the model, shown collapsed in the UI.
    var attachmentText: String?
    var conversation: Conversation?

    init(
        id: UUID = UUID(),
        role: MessageRole,
        text: String,
        createdAt: Date = .now,
        modelRef: ModelRef? = nil,
        modelLabel: String? = nil,
        state: MessageState = .complete,
        attachmentNames: [String] = [],
        attachmentText: String? = nil
    ) {
        self.id = id
        self.roleRaw = role.rawValue
        self.text = text
        self.createdAt = createdAt
        self.modelRefRaw = modelRef?.rawValue
        self.modelLabel = modelLabel
        self.stateRaw = state.rawValue
        self.attachmentNames = attachmentNames
        self.attachmentText = attachmentText
    }

    var role: MessageRole {
        get { MessageRole(rawValue: roleRaw) ?? .user }
        set { roleRaw = newValue.rawValue }
    }

    var state: MessageState {
        get { MessageState(rawValue: stateRaw) ?? .complete }
        set { stateRaw = newValue.rawValue }
    }

    var modelRef: ModelRef? {
        get { modelRefRaw.flatMap(ModelRef.init(rawValue:)) }
        set { modelRefRaw = newValue?.rawValue }
    }

    /// The text sent to the model: the visible message plus any extracted attachment text.
    var promptText: String {
        guard let attachmentText, !attachmentText.isEmpty else { return text }
        let names = attachmentNames.joined(separator: ", ")
        return text + "\n\n[Attached: \(names)]\n" + attachmentText
    }
}
