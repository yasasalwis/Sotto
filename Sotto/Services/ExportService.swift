import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ConversationExport: Codable {
    struct MessageExport: Codable {
        var role: String
        var text: String
        var createdAt: Date
        var model: String?
        var attachments: [String]
    }

    struct ConversationRecord: Codable {
        var id: UUID
        var title: String
        var createdAt: Date
        var updatedAt: Date
        var model: String
        var messages: [MessageExport]
    }

    var exportedAt: Date
    var app: String
    var conversations: [ConversationRecord]

    static func make(from conversations: [Conversation]) -> ConversationExport {
        ConversationExport(
            exportedAt: .now,
            app: "Sotto",
            conversations: conversations.map { conversation in
                ConversationRecord(
                    id: conversation.id,
                    title: conversation.title,
                    createdAt: conversation.createdAt,
                    updatedAt: conversation.updatedAt,
                    model: conversation.modelRefRaw,
                    messages: conversation.orderedMessages.map { message in
                        MessageExport(
                            role: message.role.rawValue,
                            text: message.text,
                            createdAt: message.createdAt,
                            model: message.modelLabel,
                            attachments: message.attachmentNames
                        )
                    }
                )
            }
        )
    }

    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    func markdown() -> String {
        var output = "# Sotto export\n\nExported \(exportedAt.formatted(date: .long, time: .shortened))\n"
        for conversation in conversations {
            output += "\n---\n\n## \(conversation.title)\n\n_Model: \(conversation.model)_\n\n"
            for message in conversation.messages {
                let speaker = message.role == "user" ? "You" : (message.model ?? "Assistant")
                output += "**\(speaker)**\n\n\(message.text)\n\n"
            }
        }
        return output
    }
}

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .plainText] }
    static var writableContentTypes: [UTType] { [.json, .plainText] }

    var data: Data
    var contentType: UTType

    init(data: Data, contentType: UTType) {
        self.data = data
        self.contentType = contentType
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        contentType = configuration.contentType
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
