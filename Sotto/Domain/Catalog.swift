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

    /// The only host a catalog entry may point at. Weights are large, unsigned files that get
    /// loaded straight into the inference engine, so where they come from is pinned in code
    /// rather than taken on trust from the catalog.
    static let allowedHost = "huggingface.co"

    static func loadBundled() throws -> ModelCatalog {
        guard let url = Bundle.main.url(forResource: "models", withExtension: "json") else {
            throw CatalogError.missingBundledCatalog
        }
        let data = try Data(contentsOf: url)
        return try decode(data)
    }

    static func decode(_ data: Data) throws -> ModelCatalog {
        let catalog = try JSONDecoder().decode(ModelCatalog.self, from: data)
        try catalog.validate()
        return catalog
    }

    /// Rejects an entry whose download would leave the pinned host, or over plain HTTP.
    func validate() throws {
        for entry in entries {
            guard entry.url.scheme?.lowercased() == "https" else {
                throw CatalogError.untrustedEntry(entry.id)
            }
            guard let host = entry.url.host()?.lowercased(),
                  host == Self.allowedHost || host.hasSuffix(".\(Self.allowedHost)") else {
                throw CatalogError.untrustedEntry(entry.id)
            }
        }
    }
}

enum CatalogError: Error, LocalizedError {
    case missingBundledCatalog
    case untrustedEntry(String)

    var errorDescription: String? {
        switch self {
        case .missingBundledCatalog:
            return "The bundled model catalog is missing."
        case .untrustedEntry(let id):
            return "The catalog entry “\(id)” does not download from \(ModelCatalog.allowedHost)."
        }
    }
}
