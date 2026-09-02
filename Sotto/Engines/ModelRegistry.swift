import Foundation

/// A model as the UI sees it: Apple's system model or an installed GGUF file.
struct ModelDescriptor: Identifiable, Hashable {
    enum Kind: Hashable {
        case apple
        case gguf
    }

    var ref: ModelRef
    var kind: Kind
    var name: String
    /// "3B · on-device" or "Q4_K_M · local".
    var detail: String
    /// Sidebar-style label, e.g. "qwen2.5-7b" or "apple · on-device".
    var shortLabel: String
    var isAvailable: Bool
    var unavailableReason: String?
    var contextLength: Int
    var measuredTokensPerSecond: Double?
    var sizeBytes: Int64?
    var glyph: String

    var id: String { ref.rawValue }

    var throughputLabel: String {
        guard let measured = measuredTokensPerSecond else { return kind == .apple ? "not measured" : "not measured" }
        return Format.tokensPerSecond(measured, approximate: kind == .apple, fractionDigits: 0)
    }
}

enum ModelRegistry {
    static func appleDescriptor() -> ModelDescriptor {
        let reason = AppleIntelligenceEngine.unavailableReason
        return ModelDescriptor(
            ref: .apple,
            kind: .apple,
            name: "Apple Intelligence",
            detail: "3B · on-device",
            shortLabel: ModelNaming.appleShortLabel,
            isAvailable: reason == nil,
            unavailableReason: reason,
            contextLength: AppleIntelligenceEngine.fixedContextLength,
            measuredTokensPerSecond: AppleThroughput.lastMeasured,
            sizeBytes: nil,
            glyph: ""
        )
    }

    static func descriptor(for record: InstalledModel, runtime: ModelRuntime) -> ModelDescriptor {
        let fileExists = runtime.store.fileExists(for: record)
        let fit = runtime.fitsInMemory(record)
        var reason: String?
        if !fileExists {
            reason = "weights missing from disk"
        } else if !fit.fits {
            reason = "needs \(Format.bytes(fit.needed)) · not enough memory"
        }
        return ModelDescriptor(
            ref: record.modelRef,
            kind: .gguf,
            name: record.name,
            detail: "\(record.quantization) · local",
            shortLabel: record.shortLabel,
            isAvailable: reason == nil,
            unavailableReason: reason,
            contextLength: min(runtime.settings.contextLength, max(record.contextLength, 512)),
            measuredTokensPerSecond: record.measuredTokensPerSecond,
            sizeBytes: record.fileSizeBytes,
            glyph: record.glyph
        )
    }

    static func all(installed: [InstalledModel], runtime: ModelRuntime) -> [ModelDescriptor] {
        [appleDescriptor()] + installed.sorted { $0.importedAt > $1.importedAt }.map { descriptor(for: $0, runtime: runtime) }
    }

    static func descriptor(for ref: ModelRef, installed: [InstalledModel], runtime: ModelRuntime) -> ModelDescriptor? {
        switch ref {
        case .apple:
            return appleDescriptor()
        case .gguf(let id):
            guard let record = installed.first(where: { $0.id == id }) else { return nil }
            return descriptor(for: record, runtime: runtime)
        }
    }

    static func engine(for ref: ModelRef, installed: [InstalledModel], runtime: ModelRuntime) throws -> InferenceEngine {
        switch ref {
        case .apple:
            return AppleIntelligenceEngine()
        case .gguf(let id):
            guard let record = installed.first(where: { $0.id == id }) else {
                throw EngineError.modelNotInstalled
            }
            return GGUFEngine(record: record, runtime: runtime)
        }
    }

    /// The best default model: Apple when available, otherwise the most recently used GGUF.
    static func preferredDefault(installed: [InstalledModel], settings: SettingsStore) -> ModelRef {
        let preferred = settings.defaultModelRef
        switch preferred {
        case .apple where AppleIntelligenceEngine.isAvailable:
            return .apple
        case .gguf(let id) where installed.contains(where: { $0.id == id }):
            return preferred
        default:
            if AppleIntelligenceEngine.isAvailable { return .apple }
            if let first = installed.sorted(by: { ($0.lastUsedAt ?? $0.importedAt) > ($1.lastUsedAt ?? $1.importedAt) }).first {
                return first.modelRef
            }
            return .apple
        }
    }
}

/// Apple's model exposes no token counts, so throughput is estimated from streamed text and
/// remembered for the library and pickers.
enum AppleThroughput {
    private static let key = "appleMeasuredTokensPerSecond"

    static var lastMeasured: Double? {
        let value = UserDefaults.standard.double(forKey: key)
        return value > 0 ? value : nil
    }

    static func record(_ sample: Double) {
        guard sample > 0 else { return }
        let smoothed: Double
        if let existing = lastMeasured {
            smoothed = existing * 0.7 + sample * 0.3
        } else {
            smoothed = sample
        }
        UserDefaults.standard.set(smoothed, forKey: key)
    }
}
