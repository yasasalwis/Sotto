import Foundation
import SwiftData

@Model
final class Conversation {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    /// Raw `ModelRef` string of the model this conversation uses.
    var modelRefRaw: String
    var personaID: UUID?
    var temperatureOverride: Double?
    var topPOverride: Double?
    var maxTokensOverride: Int?
    var isTitleGenerated: Bool
    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    var messages: [Message]

    init(
        id: UUID = UUID(),
        title: String = "New chat",
        modelRef: ModelRef,
        personaID: UUID? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.modelRefRaw = modelRef.rawValue
        self.personaID = personaID
        self.isTitleGenerated = false
        self.messages = []
    }

    var modelRef: ModelRef {
        get { ModelRef(rawValue: modelRefRaw) ?? .apple }
        set { modelRefRaw = newValue.rawValue }
    }

    var orderedMessages: [Message] {
        messages.sorted { $0.createdAt < $1.createdAt }
    }

    var lastActivity: Date {
        max(updatedAt, messages.map(\.createdAt).max() ?? updatedAt)
    }

    var isEmpty: Bool { messages.isEmpty }
}
