import Foundation

struct CatalogEntry: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var family: String
    var publisher: String
    var repository: String
    var fileName: String
    var url: URL
    var sizeBytes: Int64
    var quantization: String
    var parameterLabel: String
    var contextLength: Int
    var license: String
    var summary: String

    /// Rough working-set requirement: weights plus headroom for the KV cache and activations.
    var estimatedMemoryBytes: Int64 {
        Int64(Double(sizeBytes) * 1.25) + 512_000_000
    }

    var glyph: String { String(name.prefix(1)).uppercased() }
}

struct ModelCatalog: Codable, Sendable {
    var version: Int
    var updatedAt: String
    var entries: [CatalogEntry]

    static func loadBundled() throws -> ModelCatalog {
        guard let url = Bundle.main.url(forResource: "models", withExtension: "json") else {
            throw CatalogError.missingBundledCatalog
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ModelCatalog.self, from: data)
    }

    static func decode(_ data: Data) throws -> ModelCatalog {
        try JSONDecoder().decode(ModelCatalog.self, from: data)
    }
}

enum CatalogError: Error, LocalizedError {
    case missingBundledCatalog

    var errorDescription: String? {
        "The bundled model catalog is missing."
    }
}
