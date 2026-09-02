import Foundation
import LlamaKit
import Observation
import os

/// Holds at most one loaded GGUF model and tracks its throughput for the inspector.
@Observable
final class ModelRuntime {
    enum LoadState: Equatable {
        case idle
        case loading(name: String, progress: Double)
        case loaded(name: String)
        case failed(String)

        var label: String {
            switch self {
            case .idle: return "idle"
            case .loading: return "loading"
            case .loaded: return "loaded"
            case .failed: return "failed"
            }
        }
    }

    static let throughputSampleCount = 8

    private(set) var state: LoadState = .idle
    private(set) var loadedModelID: UUID?
    private(set) var loadedModel: LlamaModel?
    private(set) var loadedAt: Date?
    private(set) var activeGenerations = 0
    private(set) var throughputHistory: [Double] = []
    private(set) var lastTokensPerSecond: Double?
    private(set) var lastPromptTokens: Int?
    private(set) var lastContextUsage: Double = 0

    @ObservationIgnored private var loadTask: Task<LlamaModel, Error>?
    @ObservationIgnored private var idleTask: Task<Void, Never>?
    @ObservationIgnored let store: ModelStore
    @ObservationIgnored let settings: SettingsStore

    init(store: ModelStore, settings: SettingsStore) {
        self.store = store
        self.settings = settings
    }

    var isGenerating: Bool { activeGenerations > 0 }

    /// Bytes the loaded model is expected to hold resident.
    func estimatedMemory(for record: InstalledModel, contextLength: Int) -> UInt64 {
        let weights = UInt64(max(record.fileSizeBytes, 0))
        let kvPerToken: UInt64 = 128 * 1024 // conservative, Q4 7B-class with 32 layers, f16 cache
        return weights + weights / 8 + UInt64(contextLength) * kvPerToken
    }

    /// Whether the model is likely to fit right now.
    func fitsInMemory(_ record: InstalledModel) -> (fits: Bool, needed: UInt64, available: UInt64) {
        let needed = estimatedMemory(for: record, contextLength: min(settings.contextLength, max(record.contextLength, 512)))
        let available = DeviceCapabilities.availableMemoryBytes()
        #if os(iOS)
        let fits = Double(needed) <= Double(available) * 0.95
        #else
        let physical = DeviceCapabilities.physicalMemoryBytes
        let fits = needed <= (physical > 2_000_000_000 ? physical - 2_000_000_000 : physical)
        #endif
        return (fits, needed, available)
    }

    /// Returns the loaded model for `record`, loading it (and unloading any other) if necessary.
    func model(for record: InstalledModel) async throws -> LlamaModel {
        markActivity()
        if let loadedModel, loadedModelID == record.id {
            return loadedModel
        }
        if let loadTask, loadedModelID == record.id {
            return try await loadTask.value
        }
        loadTask?.cancel()
        await unload()

        let url = store.fileURL(for: record)
        guard store.fileExists(for: record) else {
            throw EngineError.modelFileMissing(record.name)
        }
        let fit = fitsInMemory(record)
        guard fit.fits else {
            throw EngineError.notEnoughMemory(needed: fit.needed, available: fit.available)
        }

        var options = LlamaLoadOptions()
        options.contextLength = min(settings.contextLength, max(record.contextLength, 512))
        options.gpuLayers = settings.gpuLayers
        options.threads = settings.threadCount > 0 ? settings.threadCount : nil
        options.useFlashAttention = settings.flashAttention.boolValue

        let name = record.name
        loadedModelID = record.id
        state = .loading(name: name, progress: 0)
        Log.engine.info("Loading \(name, privacy: .public) with context \(options.contextLength)")
        let task = Task<LlamaModel, Error> {
            try await LlamaModel.load(url: url, options: options) { progress in
                Task { @MainActor [weak self] in
                    guard let self, case .loading = self.state else { return }
                    self.state = .loading(name: name, progress: progress)
                }
            }
        }
        loadTask = task
        do {
            let model = try await task.value
            loadTask = nil
            loadedModel = model
            loadedAt = .now
            state = .loaded(name: name)
            record.lastUsedAt = .now
            Log.engine.info("Loaded \(name, privacy: .public): ctx=\(model.contextLength) gpuLayers=\(model.gpuLayers) threads=\(model.threadCount)")
            scheduleIdleUnload()
            return model
        } catch {
            loadTask = nil
            loadedModelID = nil
            state = .failed(error.localizedDescription)
            Log.engine.error("Failed to load \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func unload() async {
        idleTask?.cancel()
        idleTask = nil
        guard let model = loadedModel else {
            if case .failed = state { state = .idle }
            return
        }
        loadedModel = nil
        loadedModelID = nil
        loadedAt = nil
        state = .idle
        await model.unload()
        Log.engine.info("Unloaded \(model.info.name, privacy: .public)")
    }

    func beginGeneration() {
        activeGenerations += 1
        idleTask?.cancel()
    }

    func endGeneration() {
        activeGenerations = max(0, activeGenerations - 1)
        scheduleIdleUnload()
    }

    func record(stats: LlamaGenerationStats, contextLength: Int) {
        if stats.tokensPerSecond > 0 {
            lastTokensPerSecond = stats.tokensPerSecond
            throughputHistory.append(stats.tokensPerSecond)
            if throughputHistory.count > Self.throughputSampleCount {
                throughputHistory.removeFirst(throughputHistory.count - Self.throughputSampleCount)
            }
        }
        lastPromptTokens = stats.promptTokens
        lastContextUsage = contextLength > 0 ? Double(stats.promptTokens + stats.generatedTokens) / Double(contextLength) : 0
    }

    func recordContextUsage(tokens: Int, contextLength: Int) {
        lastContextUsage = contextLength > 0 ? Double(tokens) / Double(contextLength) : 0
    }

    func markActivity() {
        scheduleIdleUnload()
    }

    private func scheduleIdleUnload() {
        idleTask?.cancel()
        guard loadedModel != nil, !settings.keepModelLoaded, settings.idleUnloadMinutes > 0, activeGenerations == 0 else { return }
        let minutes = settings.idleUnloadMinutes
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled, let self, self.activeGenerations == 0 else { return }
            Log.engine.info("Idle for \(minutes) min; unloading model")
            await self.unload()
        }
    }
}
