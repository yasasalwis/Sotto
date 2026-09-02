import Foundation
import SwiftData

enum DownloadState: String, Codable, Sendable {
    case queued
    case downloading
    case paused
    case failed
    case completed
}

@Model
final class ModelDownload {
    @Attribute(.unique) var id: UUID
    var catalogID: String
    var name: String
    var fileName: String
    var urlString: String
    var totalBytes: Int64
    var receivedBytes: Int64
    var stateRaw: String
    var errorMessage: String?
    @Attribute(.externalStorage) var resumeData: Data?
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), catalogID: String, name: String, fileName: String, url: URL, totalBytes: Int64) {
        self.id = id
        self.catalogID = catalogID
        self.name = name
        self.fileName = fileName
        self.urlString = url.absoluteString
        self.totalBytes = totalBytes
        self.receivedBytes = 0
        self.stateRaw = DownloadState.queued.rawValue
        self.createdAt = .now
        self.updatedAt = .now
    }

    var state: DownloadState {
        get { DownloadState(rawValue: stateRaw) ?? .failed }
        set { stateRaw = newValue.rawValue }
    }

    var url: URL? { URL(string: urlString) }

    var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(receivedBytes) / Double(totalBytes)
    }
}
