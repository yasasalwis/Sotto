import Foundation
import os

/// Optional weekly check of the curated repositories on Hugging Face for new quantizations.
/// Off by default; only runs when the user enables "Model catalog updates".
struct CatalogRefreshResult: Codable, Hashable {
    struct RepositoryUpdate: Codable, Hashable {
        var repository: String
        var knownFileSize: Int64?
        var otherQuantizations: [String]
    }

    var checkedAt: Date
    var updates: [RepositoryUpdate]

    var newQuantizationCount: Int {
        updates.reduce(0) { $0 + $1.otherQuantizations.count }
    }
}

enum CatalogRefresher {
    static let interval: TimeInterval = 7 * 24 * 3600
    static let storageKey = "catalogRefreshResult"

    private struct TreeEntry: Decodable {
        var path: String
        var size: Int64?
    }

    static func loadLastResult(defaults: UserDefaults = .standard) -> CatalogRefreshResult? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(CatalogRefreshResult.self, from: data)
    }

    static func isDue(settings: SettingsStore, now: Date = .now) -> Bool {
        guard settings.catalogUpdates else { return false }
        guard let last = settings.catalogLastChecked else { return true }
        return now.timeIntervalSince(last) >= interval
    }

    /// Fetches the file list of every catalog repository and records what changed.
    static func refresh(catalog: ModelCatalog, settings: SettingsStore, defaults: UserDefaults = .standard) async -> CatalogRefreshResult? {
        var updates: [CatalogRefreshResult.RepositoryUpdate] = []
        var bytesSent: Int64 = 0
        for entry in catalog.entries {
            guard let url = URL(string: "https://huggingface.co/api/models/\(entry.repository)/tree/main") else { continue }
            do {
                let (data, sent) = try await AccountedURLSession.get(url)
                bytesSent += sent
                let tree = try JSONDecoder().decode([TreeEntry].self, from: data)
                let ggufs = tree.filter { $0.path.lowercased().hasSuffix(".gguf") }
                let known = ggufs.first { $0.path == entry.fileName }
                let others = ggufs.map(\.path).filter { $0 != entry.fileName }.sorted()
                updates.append(.init(repository: entry.repository, knownFileSize: known?.size, otherQuantizations: others))
            } catch {
                Log.downloads.notice("Catalog check failed for \(entry.repository, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        settings.recordBytesSent(bytesSent)
        settings.catalogLastChecked = .now
        guard !updates.isEmpty else { return nil }
        let result = CatalogRefreshResult(checkedAt: .now, updates: updates)
        if let data = try? JSONEncoder().encode(result) {
            defaults.set(data, forKey: storageKey)
        }
        Log.downloads.info("Catalog refreshed: \(updates.count) repositories, \(result.newQuantizationCount) other quantizations listed")
        return result
    }
}

/// A one-shot GET that reports how many bytes the request actually put on the wire.
enum AccountedURLSession {
    static func get(_ url: URL) async throws -> (Data, Int64) {
        var request = URLRequest(url: url)
        request.setValue("Sotto/1.0 (local-first chat client)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        return try await withCheckedThrowingContinuation { continuation in
            let box = TaskBox()
            let completion = CompletionBox(continuation: continuation, box: box)
            box.task = URLSession.shared.dataTask(with: request) { data, response, error in
                let sent = completion.box.task?.countOfBytesSent ?? 0
                if let error {
                    completion.continuation.resume(throwing: error)
                    return
                }
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data else {
                    completion.continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                completion.continuation.resume(returning: (data, sent))
            }
            box.task?.resume()
        }
    }

    private final class TaskBox: @unchecked Sendable {
        var task: URLSessionDataTask?
    }

    private struct CompletionBox: @unchecked Sendable {
        let continuation: CheckedContinuation<(Data, Int64), Error>
        let box: TaskBox
    }
}
