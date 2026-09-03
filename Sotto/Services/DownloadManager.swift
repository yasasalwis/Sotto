import Foundation
import Observation
import SwiftData
import os

/// Background-session downloads for catalog models: resumable, pausable, Wi-Fi aware.
/// Completed files are validated as GGUF before they enter the library.
@Observable
@MainActor
final class DownloadManager: NSObject, URLSessionDownloadDelegate {
    struct LiveProgress: Equatable {
        var received: Int64
        var total: Int64
        var bytesPerSecond: Double
        var updatedAt: Date

        var fraction: Double { total > 0 ? Double(received) / Double(total) : 0 }
        var secondsRemaining: Double? {
            guard bytesPerSecond > 0, total > received else { return nil }
            return Double(total - received) / bytesPerSecond
        }
    }

    static let sessionIdentifier = "lk.eonix.sotto.downloads"

    private(set) var live: [UUID: LiveProgress] = [:]
    var backgroundCompletionHandler: (() -> Void)?

    @ObservationIgnored private var session: URLSession!
    /// Used when the background transfer service will not talk to us. Downloads then run in
    /// process: they stop if the app quits, which is better than not downloading at all.
    @ObservationIgnored private var foregroundSession: URLSession?
    /// Records already retried on the foreground session, so a genuine failure is not retried forever.
    @ObservationIgnored private var retriedInForeground: Set<UUID> = []
    @ObservationIgnored private var tasks: [UUID: URLSessionDownloadTask] = [:]
    @ObservationIgnored private var lastPersisted: [UUID: Date] = [:]
    @ObservationIgnored private var speedWindow: [UUID: (Date, Int64)] = [:]
    @ObservationIgnored let store: ModelStore
    @ObservationIgnored let settings: SettingsStore
    @ObservationIgnored let container: ModelContainer
    @ObservationIgnored let catalog: ModelCatalog
    nonisolated let stagingDirectory: URL

    init(store: ModelStore, settings: SettingsStore, container: ModelContainer, catalog: ModelCatalog) {
        self.store = store
        self.settings = settings
        self.container = container
        self.catalog = catalog
        self.stagingDirectory = store.stagingDirectory
        super.init()
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.waitsForConnectivity = true
        configuration.allowsCellularAccess = Self.allowsCellular(wifiOnly: settings.wifiOnlyDownloads)
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        Task { await restore() }
    }

    private var context: ModelContext { container.mainContext }

    // MARK: - Public API

    func download(_ record: ModelDownload) -> ModelDownload? {
        context.model(for: record.persistentModelID) as? ModelDownload
    }

    func isDownloading(catalogID: String) -> Bool {
        (try? context.fetch(FetchDescriptor<ModelDownload>()))?.contains { $0.catalogID == catalogID } ?? false
    }

    @discardableResult
    func start(_ entry: CatalogEntry) throws -> ModelDownload {
        let existing = try context.fetch(FetchDescriptor<ModelDownload>())
        if let current = existing.first(where: { $0.catalogID == entry.id }) {
            resume(current)
            return current
        }
        let free = store.freeDiskBytes
        if free > 0, entry.sizeBytes > free {
            throw ModelStoreError.notEnoughDiskSpace(needed: entry.sizeBytes, available: free)
        }
        let record = ModelDownload(catalogID: entry.id, name: entry.name, fileName: entry.fileName, url: entry.url, totalBytes: entry.sizeBytes)
        context.insert(record)
        try context.save()
        Log.downloads.info("Queued download \(entry.name, privacy: .public)")
        beginTask(for: record, resumeData: nil)
        return record
    }

    func pause(_ record: ModelDownload) {
        guard let task = tasks[record.id] else {
            record.state = .paused
            persist()
            return
        }
        record.state = .paused
        record.updatedAt = .now
        persist()
        // URLSession calls this back on its own queue, so the record itself must not travel:
        // a SwiftData model belongs to the main actor's context. Only its id crosses, and the
        // record is fetched again on the way back in — by then the download may have been
        // deleted, which is why the task entry is cleared before the record is looked up.
        let id = record.id
        task.cancel { [weak self] data in
            guard let manager = self else { return }
            Task { @MainActor in
                manager.tasks[id] = nil
                guard let record = manager.record(withID: id) else { return }
                record.resumeData = data
                manager.persist()
                Log.downloads.info("Paused \(record.name, privacy: .public)")
            }
        }
    }

    func resume(_ record: ModelDownload) {
        guard tasks[record.id] == nil else { return }
        beginTask(for: record, resumeData: record.resumeData)
        record.resumeData = nil
        record.errorMessage = nil
        record.state = .downloading
        record.updatedAt = .now
        persist()
        Log.downloads.info("Resumed \(record.name, privacy: .public)")
    }

    func cancel(_ record: ModelDownload) {
        if let task = tasks[record.id] {
            task.cancel()
            tasks[record.id] = nil
        }
        live[record.id] = nil
        context.delete(record)
        persist()
        Log.downloads.info("Cancelled \(record.name, privacy: .public)")
    }

    func updateCellularPolicy() {
        // Background sessions fix `allowsCellularAccess` at creation; new tasks carry the policy on their request.
        Log.downloads.info("Wi-Fi only downloads: \(self.settings.wifiOnlyDownloads)")
    }

    // MARK: - Internals

    private func beginTask(for record: ModelDownload, resumeData: Data?, inForeground: Bool = false) {
        let transport = inForeground ? foregroundTransport() : session!
        let task: URLSessionDownloadTask
        if let resumeData {
            task = transport.downloadTask(withResumeData: resumeData)
        } else {
            guard let url = record.url else {
                record.state = .failed
                record.errorMessage = "The download address is invalid."
                persist()
                return
            }
            var request = URLRequest(url: url)
            request.allowsCellularAccess = Self.allowsCellular(wifiOnly: settings.wifiOnlyDownloads)
            request.setValue("Sotto/1.0 (local-first chat client)", forHTTPHeaderField: "User-Agent")
            task = transport.downloadTask(with: request)
        }
        task.taskDescription = record.id.uuidString
        task.countOfBytesClientExpectsToReceive = record.totalBytes
        tasks[record.id] = task
        record.state = .downloading
        live[record.id] = LiveProgress(received: record.receivedBytes, total: record.totalBytes, bytesPerSecond: 0, updatedAt: .now)
        task.resume()
    }

    /// Reattaches to downloads the system kept running across launches. Reading `allTasks`
    /// suspends, and the user can press Download in that window, so anything started meanwhile is
    /// left strictly alone: its task stays in `tasks` and its record keeps its state.
    private func foregroundTransport() -> URLSession {
        if let foregroundSession { return foregroundSession }
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.allowsCellularAccess = Self.allowsCellular(wifiOnly: settings.wifiOnlyDownloads)
        let created = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        foregroundSession = created
        Log.downloads.notice("Background transfer unavailable; downloading in process instead")
        return created
    }

    /// "Downloads on Wi-Fi only" is an iPhone setting: it has no switch on the Mac, so it must not
    /// quietly gate the Mac's network. It matters there too because macOS reports a Personal
    /// Hotspot as cellular, and a blocked task with `waitsForConnectivity` stalls at zero bytes
    /// forever instead of failing.
    static func allowsCellular(wifiOnly: Bool) -> Bool {
        #if os(iOS)
        return !wifiOnly
        #else
        return true
        #endif
    }

    /// `nsurlsessiond` is not always reachable — notably for an app run by the test runner or from
    /// an unusual location — and it reports that only when the first task fails.
    static func isBackgroundServiceUnavailable(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorBackgroundSessionRequiresSharedContainer,
                 NSURLErrorBackgroundSessionInUseByAnotherProcess,
                 NSURLErrorBackgroundSessionWasDisconnected:
                return true
            default:
                break
            }
        }
        return nsError.localizedDescription.localizedCaseInsensitiveContains("background transfer service")
    }

    private func restore() async {
        let liveTasks = await session.allTasks.compactMap { $0 as? URLSessionDownloadTask }
        var byID: [UUID: URLSessionDownloadTask] = [:]
        for task in liveTasks {
            if let description = task.taskDescription, let id = UUID(uuidString: description) {
                byID[id] = task
            }
        }
        for (id, task) in byID where tasks[id] == nil {
            tasks[id] = task
        }
        guard let records = try? context.fetch(FetchDescriptor<ModelDownload>()) else { return }
        var orphaned = 0
        for record in records {
            if let task = byID[record.id] {
                record.state = .downloading
                live[record.id] = LiveProgress(received: task.countOfBytesReceived, total: record.totalBytes, bytesPerSecond: 0, updatedAt: .now)
                continue
            }
            guard Self.isOrphaned(state: record.state, isTracked: tasks[record.id] != nil) else { continue }
            orphaned += 1
            record.state = record.resumeData != nil ? .paused : .failed
            if record.state == .failed {
                record.errorMessage = "The download was interrupted. Tap retry to start again."
            }
        }
        persist()
        Log.downloads.info("Restored \(records.count) download records, \(byID.count) live tasks, \(orphaned) orphaned")
    }

    /// A record left mid-flight by a previous launch: not attached to a live task, and not one we
    /// started ourselves since launching.
    static func isOrphaned(state: DownloadState, isTracked: Bool) -> Bool {
        guard !isTracked else { return false }
        return state == .downloading || state == .queued
    }

    private func persist() {
        do {
            try context.save()
        } catch {
            Log.persistence.error("Download state save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func record(withID id: UUID) -> ModelDownload? {
        var descriptor = FetchDescriptor<ModelDownload>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func handleProgress(id: UUID, received: Int64, expected: Int64) {
        let now = Date()
        var speed = live[id]?.bytesPerSecond ?? 0
        if let (previousDate, previousBytes) = speedWindow[id] {
            let interval = now.timeIntervalSince(previousDate)
            if interval >= 0.5 {
                let instant = Double(received - previousBytes) / interval
                speed = speed > 0 ? speed * 0.6 + instant * 0.4 : instant
                speedWindow[id] = (now, received)
            }
        } else {
            speedWindow[id] = (now, received)
        }
        let total = expected > 0 ? expected : (live[id]?.total ?? 0)
        live[id] = LiveProgress(received: received, total: total, bytesPerSecond: speed, updatedAt: now)

        if let last = lastPersisted[id], now.timeIntervalSince(last) < 2 { return }
        lastPersisted[id] = now
        if let record = record(withID: id) {
            record.receivedBytes = received
            if total > 0 { record.totalBytes = total }
            record.updatedAt = now
            persist()
        }
    }

    /// The system is holding the request because it has no network it is allowed to use. Say so,
    /// rather than showing a download that never moves.
    private func markWaitingForNetwork(id: UUID) {
        guard let record = record(withID: id), record.receivedBytes == 0 else { return }
        record.errorMessage = "Waiting for a network Sotto is allowed to use."
        record.updatedAt = .now
        persist()
        Log.downloads.notice("Download for \(record.name, privacy: .public) is waiting for connectivity")
    }

    private func handleCompletion(id: UUID, stagedFile: URL, bytesSent: Int64) {
        settings.recordBytesSent(bytesSent)
        tasks[id] = nil
        live[id] = nil
        speedWindow[id] = nil
        guard let record = record(withID: id) else {
            try? FileManager.default.removeItem(at: stagedFile)
            return
        }
        do {
            guard try ModelStore.hasGGUFMagic(stagedFile) else {
                throw ModelStoreError.notAGGUFFile
            }
            let fileName = store.uniqueFileName(for: record.fileName)
            let destination = store.modelsDirectory.appendingPathComponent(fileName)
            try FileManager.default.moveItem(at: stagedFile, to: destination)
            let entry = catalog.entries.first { $0.id == record.catalogID }
            let installed = try store.register(fileAt: destination, source: .catalog, catalogID: record.catalogID, preferredName: entry?.name ?? record.name, in: context)
            context.delete(record)
            persist()
            Log.downloads.info("Installed \(installed.name, privacy: .public) from catalog")
        } catch {
            try? FileManager.default.removeItem(at: stagedFile)
            record.state = .failed
            record.errorMessage = error.localizedDescription
            record.updatedAt = .now
            persist()
            Log.downloads.error("Download finished but install failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handleFailure(id: UUID, error: Error, resumeData: Data?, bytesSent: Int64) {
        settings.recordBytesSent(bytesSent)
        tasks[id] = nil
        live[id] = nil
        speedWindow[id] = nil
        guard let record = record(withID: id) else { return }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            if record.state == .paused {
                record.resumeData = resumeData ?? record.resumeData
                persist()
            }
            return
        }
        if Self.isBackgroundServiceUnavailable(error), !retriedInForeground.contains(id) {
            retriedInForeground.insert(id)
            record.state = .downloading
            record.errorMessage = nil
            record.updatedAt = .now
            persist()
            beginTask(for: record, resumeData: resumeData, inForeground: true)
            return
        }
        record.state = resumeData != nil ? .paused : .failed
        record.resumeData = resumeData
        record.errorMessage = error.localizedDescription
        record.updatedAt = .now
        persist()
        Log.downloads.error("Download failed for \(record.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }

    // MARK: - URLSessionDownloadDelegate (called on the session queue)

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let description = downloadTask.taskDescription, let id = UUID(uuidString: description) else { return }
        Task { @MainActor in
            self.handleProgress(id: id, received: totalBytesWritten, expected: totalBytesExpectedToWrite)
        }
    }

    nonisolated func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        guard let description = task.taskDescription, let id = UUID(uuidString: description) else { return }
        Task { @MainActor in
            self.markWaitingForNetwork(id: id)
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let description = downloadTask.taskDescription, let id = UUID(uuidString: description) else {
            try? FileManager.default.removeItem(at: location)
            return
        }
        let staged = stagingDirectory.appendingPathComponent("\(id.uuidString).gguf")
        try? FileManager.default.removeItem(at: staged)
        do {
            try FileManager.default.moveItem(at: location, to: staged)
        } catch {
            let message = error.localizedDescription
            let sent = downloadTask.countOfBytesSent
            Task { @MainActor in
                self.handleFailure(id: id, error: ModelStoreError.copyFailed(message), resumeData: nil, bytesSent: sent)
            }
            return
        }
        let sent = downloadTask.countOfBytesSent
        Task { @MainActor in
            self.handleCompletion(id: id, stagedFile: staged, bytesSent: sent)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let description = task.taskDescription, let id = UUID(uuidString: description) else { return }
        let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        let sent = task.countOfBytesSent
        Task { @MainActor in
            self.handleFailure(id: id, error: error, resumeData: resumeData, bytesSent: sent)
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }
}
