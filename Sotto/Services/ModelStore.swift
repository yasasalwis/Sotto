import Foundation
import LlamaKit
import SwiftData
import UniformTypeIdentifiers
import os

extension UTType {
    static let gguf = UTType(exportedAs: "lk.eonix.sotto.gguf", conformingTo: .data)
}

enum ModelStoreError: LocalizedError {
    case notAGGUFFile
    case notEnoughDiskSpace(needed: Int64, available: Int64)
    case accessDenied
    case copyFailed(String)
    case fileMissing(String)

    var errorDescription: String? {
        switch self {
        case .notAGGUFFile:
            return "That file isn't a GGUF model. Sotto imports .gguf files only."
        case .notEnoughDiskSpace(let needed, let available):
            return "Not enough free space. The model needs \(Format.bytes(needed)) and \(Format.bytes(available)) is available."
        case .accessDenied:
            return "Sotto wasn't allowed to read that file."
        case .copyFailed(let reason):
            return "The model couldn't be copied into Sotto's library: \(reason)"
        case .fileMissing(let name):
            return "The weights for “\(name)” are no longer on disk."
        }
    }
}

/// Owns the on-disk model library: import, delete, storage accounting.
@Observable
final class ModelStore {
    static let ggufMagic: [UInt8] = Array("GGUF".utf8)

    let baseDirectory: URL
    let modelsDirectory: URL
    let stagingDirectory: URL
    let diagnosticsDirectory: URL

    init(baseDirectory: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.baseDirectory = baseDirectory ?? support.appendingPathComponent("Sotto", isDirectory: true)
        self.modelsDirectory = self.baseDirectory.appendingPathComponent("Models", isDirectory: true)
        self.stagingDirectory = self.baseDirectory.appendingPathComponent("Staging", isDirectory: true)
        self.diagnosticsDirectory = self.baseDirectory.appendingPathComponent("Diagnostics", isDirectory: true)
        for directory in [self.baseDirectory, modelsDirectory, stagingDirectory, diagnosticsDirectory] {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        Self.excludeFromBackup(modelsDirectory)
    }

    func fileURL(for model: InstalledModel) -> URL {
        modelsDirectory.appendingPathComponent(model.fileName)
    }

    func fileExists(for model: InstalledModel) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: model).path(percentEncoded: false))
    }

    var freeDiskBytes: Int64 {
        DeviceCapabilities.freeDiskBytes(at: modelsDirectory)
    }

    func diskUsage(of models: [InstalledModel]) -> Int64 {
        models.reduce(0) { $0 + $1.fileSizeBytes }
    }

    /// Validates and copies a user-chosen file into the library, then records it.
    func importModel(from sourceURL: URL, into context: ModelContext) async throws -> InstalledModel {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        guard sourceURL.pathExtension.lowercased() == "gguf", try Self.hasGGUFMagic(sourceURL) else {
            throw ModelStoreError.notAGGUFFile
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: sourceURL.path(percentEncoded: false))
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let available = freeDiskBytes
        if available > 0, size > available {
            throw ModelStoreError.notEnoughDiskSpace(needed: size, available: available)
        }

        let fileName = uniqueFileName(for: sourceURL.lastPathComponent)
        let destination = modelsDirectory.appendingPathComponent(fileName)
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var copyError: Error?
        coordinator.coordinate(readingItemAt: sourceURL, options: [], error: &coordinationError) { readableURL in
            do {
                try FileManager.default.copyItem(at: readableURL, to: destination)
            } catch {
                copyError = error
            }
        }
        if let coordinationError {
            throw ModelStoreError.copyFailed(coordinationError.localizedDescription)
        }
        if let copyError {
            throw ModelStoreError.copyFailed(copyError.localizedDescription)
        }

        do {
            let record = try register(fileAt: destination, source: .imported, catalogID: nil, preferredName: nil, in: context)
            Log.models.info("Imported model \(record.name, privacy: .public) (\(Format.bytes(record.fileSizeBytes), privacy: .public))")
            return record
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    /// Records a file that is already inside the models directory (used after a catalog download).
    @discardableResult
    func register(fileAt url: URL, source: InstalledModelSource, catalogID: String?, preferredName: String?, in context: ModelContext) throws -> InstalledModel {
        guard try Self.hasGGUFMagic(url) else {
            throw ModelStoreError.notAGGUFFile
        }
        let info = try GGUFMetadata.read(at: url)
        let name = preferredName ?? (info.name == "unknown" ? ModelNaming.displayName(fromFileName: url.lastPathComponent) : info.name)
        let record = InstalledModel(
            name: name,
            fileName: url.lastPathComponent,
            fileSizeBytes: Int64(info.fileSizeBytes),
            quantization: info.quantization,
            parameterLabel: info.parameterLabel,
            parameterCount: Int64(info.parameterCount),
            architecture: info.architecture,
            contextLength: info.trainingContextLength,
            hasChatTemplate: info.hasChatTemplate,
            source: source,
            catalogID: catalogID
        )
        context.insert(record)
        try context.save()
        return record
    }

    func delete(_ model: InstalledModel, from context: ModelContext) throws {
        let url = fileURL(for: model)
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: url)
        }
        context.delete(model)
        try context.save()
        Log.models.info("Deleted model \(model.name, privacy: .public)")
    }

    /// Removes files in the models directory that no record references, and reports records whose file is gone.
    func reconcile(records: [InstalledModel]) -> [InstalledModel] {
        let referenced = Set(records.map(\.fileName))
        if let contents = try? FileManager.default.contentsOfDirectory(at: modelsDirectory, includingPropertiesForKeys: nil) {
            for url in contents where url.pathExtension.lowercased() == "gguf" && !referenced.contains(url.lastPathComponent) {
                try? FileManager.default.removeItem(at: url)
                Log.models.notice("Removed orphaned model file \(url.lastPathComponent, privacy: .public)")
            }
        }
        return records.filter { !fileExists(for: $0) }
    }

    func eraseEverything() throws {
        for directory in [modelsDirectory, stagingDirectory, diagnosticsDirectory] {
            if FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: directory)
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        Self.excludeFromBackup(modelsDirectory)
    }

    func uniqueFileName(for original: String) -> String {
        let base = (original as NSString).deletingPathExtension
        let ext = (original as NSString).pathExtension
        var candidate = original
        var counter = 2
        while FileManager.default.fileExists(atPath: modelsDirectory.appendingPathComponent(candidate).path(percentEncoded: false)) {
            candidate = "\(base)-\(counter).\(ext)"
            counter += 1
        }
        return candidate
    }

    static func hasGGUFMagic(_ url: URL) throws -> Bool {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw ModelStoreError.accessDenied
        }
        defer { try? handle.close() }
        let head = try handle.read(upToCount: 4) ?? Data()
        return Array(head) == ggufMagic
    }

    private static func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = url
        try? mutable.setResourceValues(values)
    }
}
