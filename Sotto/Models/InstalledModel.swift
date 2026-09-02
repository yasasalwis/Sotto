import Foundation
import SwiftData

enum InstalledModelSource: String, Codable, Sendable {
    case imported
    case catalog
}

@Model
final class InstalledModel {
    @Attribute(.unique) var id: UUID
    var name: String
    /// File name inside the app's models directory.
    var fileName: String
    var fileSizeBytes: Int64
    var quantization: String
    var parameterLabel: String
    var parameterCount: Int64
    var architecture: String
    var contextLength: Int
    var hasChatTemplate: Bool
    var importedAt: Date
    var sourceRaw: String
    var catalogID: String?
    var measuredTokensPerSecond: Double?
    var lastUsedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        fileName: String,
        fileSizeBytes: Int64,
        quantization: String,
        parameterLabel: String,
        parameterCount: Int64,
        architecture: String,
        contextLength: Int,
        hasChatTemplate: Bool,
        source: InstalledModelSource,
        catalogID: String? = nil,
        importedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.fileSizeBytes = fileSizeBytes
        self.quantization = quantization
        self.parameterLabel = parameterLabel
        self.parameterCount = parameterCount
        self.architecture = architecture
        self.contextLength = contextLength
        self.hasChatTemplate = hasChatTemplate
        self.sourceRaw = source.rawValue
        self.catalogID = catalogID
        self.importedAt = importedAt
    }

    var source: InstalledModelSource {
        get { InstalledModelSource(rawValue: sourceRaw) ?? .imported }
        set { sourceRaw = newValue.rawValue }
    }

    var modelRef: ModelRef { .gguf(id) }

    /// Short identifier shown in the sidebar, e.g. "qwen2.5-7b".
    var shortLabel: String {
        ModelNaming.shortLabel(for: name)
    }

    /// Single-letter glyph for the model tile.
    var glyph: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }
}
