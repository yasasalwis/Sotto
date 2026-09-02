import os

/// Unified logging namespaces. Prompts, completions and file contents are never logged;
/// only lifecycle events, counts, durations and error descriptions.
enum Log {
    static let subsystem = "lk.eonix.Sotto"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let chat = Logger(subsystem: subsystem, category: "chat")
    static let models = Logger(subsystem: subsystem, category: "models")
    static let downloads = Logger(subsystem: subsystem, category: "downloads")
    static let engine = Logger(subsystem: subsystem, category: "engine")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let privacy = Logger(subsystem: subsystem, category: "privacy")
    static let security = Logger(subsystem: subsystem, category: "security")
}
