import Foundation
import SwiftData
import os

enum PersistenceController {
    static let schema = Schema([Conversation.self, Message.self, Persona.self, InstalledModel.self, ModelDownload.self])

    static func storeURL(in baseDirectory: URL) -> URL {
        baseDirectory.appendingPathComponent("Sotto.store")
    }

    /// Builds the container. When `inMemory` is true nothing touches disk, which is how the
    /// "Store conversations" switch is honoured after relaunch.
    static func makeContainer(inMemory: Bool, baseDirectory: URL) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration("SottoMemory", schema: schema, isStoredInMemoryOnly: true)
        } else {
            configuration = ModelConfiguration("Sotto", schema: schema, url: storeURL(in: baseDirectory))
        }
        let container = try ModelContainer(for: schema, configurations: [configuration])
        if !inMemory {
            applyFileProtection(in: baseDirectory)
        }
        return container
    }

    /// Inserts the built-in personas on first launch. Idempotent.
    static func seedIfNeeded(context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Persona>())) ?? 0
        guard count == 0 else { return }
        for persona in Persona.builtInSeeds() {
            context.insert(persona)
        }
        do {
            try context.save()
            Log.persistence.info("Seeded built-in personas")
        } catch {
            Log.persistence.error("Seeding personas failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Deletes every record. Used by "Erase all data".
    static func eraseAll(context: ModelContext) throws {
        try context.delete(model: Message.self)
        try context.delete(model: Conversation.self)
        try context.delete(model: ModelDownload.self)
        try context.delete(model: InstalledModel.self)
        try context.delete(model: Persona.self)
        try context.save()
    }

    static func messageCount(context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<Message>())) ?? 0
    }

    static func conversationCount(context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<Conversation>())) ?? 0
    }

    /// On iOS the store is only readable after first unlock; on macOS FileVault covers the volume.
    private static func applyFileProtection(in baseDirectory: URL) {
        #if os(iOS)
        let base = storeURL(in: baseDirectory).path(percentEncoded: false)
        for suffix in ["", "-wal", "-shm"] {
            let path = base + suffix
            guard FileManager.default.fileExists(atPath: path) else { continue }
            do {
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: path)
            } catch {
                Log.security.error("Could not set file protection on store: \(error.localizedDescription, privacy: .public)")
            }
        }
        #endif
    }
}
