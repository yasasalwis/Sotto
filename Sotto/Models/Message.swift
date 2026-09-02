import Foundation
import SwiftData

enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

/// One tool invocation made while an assistant message was being produced.
struct ToolCallRecord: Codable, Hashable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable {
        case running
        case awaitingApproval
        case denied
        case succeeded
        case failed

        var label: String {
            switch self {
            case .running: return "running"
            case .awaitingApproval: return "waiting for you"
            case .denied: return "declined"
            case .succeeded: return "done"
            case .failed: return "failed"
            }
        }
    }

    var id: UUID
    var toolName: String
    var displayName: String
    var argumentsJSON: String
    var resultText: String
    var statusRaw: String
    var durationSeconds: Double
    var bytesSent: Int64

    init(id: UUID = UUID(), toolName: String, displayName: String, argumentsJSON: String, resultText: String = "", status: Status = .running, durationSeconds: Double = 0, bytesSent: Int64 = 0) {
        self.id = id
        self.toolName = toolName
        self.displayName = displayName
        self.argumentsJSON = argumentsJSON
        self.resultText = resultText
        self.statusRaw = status.rawValue
        self.durationSeconds = durationSeconds
        self.bytesSent = bytesSent
    }

    var status: Status {
        get { Status(rawValue: statusRaw) ?? .failed }
        set { statusRaw = newValue.rawValue }
    }

    /// "expression: 17*23, precision: 2", for display next to the tool name.
    var argumentsSummary: String {
        guard let data = argumentsJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], !object.isEmpty else {
            return argumentsJSON == "{}" ? "" : argumentsJSON
        }
        return object.keys.sorted().map { key in
            let raw = object[key].map { "\($0)" } ?? ""
            let value = raw.count > 48 ? String(raw.prefix(48)) + "…" : raw
            return "\(key): \(value)"
        }.joined(separator: ", ")
    }
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
    /// JSON-encoded `[ToolCallRecord]` for tools called while producing this message.
    var toolCallsData: Data?
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

    var toolCalls: [ToolCallRecord] {
        get {
            guard let toolCallsData else { return [] }
            return (try? JSONDecoder().decode([ToolCallRecord].self, from: toolCallsData)) ?? []
        }
        set { toolCallsData = newValue.isEmpty ? nil : (try? JSONEncoder().encode(newValue)) }
    }

    /// The text sent to the model: the visible message plus any extracted attachment text.
    var promptText: String {
        guard let attachmentText, !attachmentText.isEmpty else { return text }
        let names = attachmentNames.joined(separator: ", ")
        return text + "\n\n[Attached: \(names)]\n" + attachmentText
    }
}
