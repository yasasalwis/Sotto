import Foundation
import llama
import os

private let llamaLogger = Logger(subsystem: "lk.eonix.sotto", category: "llama.cpp")

/// Forwards llama.cpp's C logging into the unified logging system. Model weights,
/// prompts and completions never pass through this path; llama.cpp only logs
/// loader and backend diagnostics.
private let llamaLogCallback: ggml_log_callback = { level, text, _ in
    guard let text else { return }
    let message = String(cString: text).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !message.isEmpty else { return }
    switch level.rawValue {
    case GGML_LOG_LEVEL_ERROR.rawValue:
        llamaLogger.error("\(message, privacy: .public)")
    case GGML_LOG_LEVEL_WARN.rawValue:
        llamaLogger.warning("\(message, privacy: .public)")
    default:
        llamaLogger.debug("\(message, privacy: .public)")
    }
}

/// Process-wide llama.cpp lifecycle. Safe to call from any thread; initialization happens once.
public enum LlamaRuntime {
    private static let initialization: Void = {
        llama_log_set(llamaLogCallback, nil)
        llama_backend_init()
    }()

    /// Initializes the ggml backends. Called automatically before any model is loaded.
    public static func initialize() {
        _ = initialization
    }

    /// `true` when the linked build can offload layers to the GPU (Metal on Apple platforms).
    public static var supportsGPUOffload: Bool {
        initialize()
        return llama_supports_gpu_offload()
    }

    /// llama.cpp's own description of the compiled backends and CPU features.
    public static var systemInfo: String {
        initialize()
        return String(cString: llama_print_system_info())
    }

    /// The vendored llama.cpp version string.
    public static var version: String {
        String(cString: llama_version())
    }

    /// Number of performance cores, used as the default generation thread count.
    public static var recommendedThreadCount: Int {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.perflevel0.logicalcpu", &value, &size, nil, 0) == 0, value > 0 {
            return Int(value)
        }
        return max(2, ProcessInfo.processInfo.activeProcessorCount - 2)
    }
}
