import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Read-only facts about the host used for capacity checks and the inspector.
enum DeviceCapabilities {
    static var physicalMemoryBytes: UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }

    /// Memory the process could plausibly claim right now. On iOS this is the jetsam
    /// headroom; on macOS it is physical memory minus wired, active and compressed pages.
    static func availableMemoryBytes() -> UInt64 {
        #if os(iOS) && !targetEnvironment(simulator)
        return UInt64(max(os_proc_available_memory(), 0))
        #else
        // The Simulator reports a token jetsam allowance, so use the host's figures instead.
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return physicalMemoryBytes / 2 }
        let pageSize = UInt64(vm_kernel_page_size)
        let used = (UInt64(stats.wire_count) + UInt64(stats.active_count) + UInt64(stats.compressor_page_count)) * pageSize
        return physicalMemoryBytes > used ? physicalMemoryBytes - used : 0
        #endif
    }

    /// Resident footprint of this process, the same number Xcode's memory gauge shows.
    static func processFootprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return UInt64(info.phys_footprint)
    }

    static var thermalStateLabel: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    static var isThermalPressureHigh: Bool {
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical: return true
        default: return false
        }
    }

    /// What the Performance page shows next to "Chip".
    ///
    /// On the Mac `machdep.cpu.brand_string` is the chip and nothing more is needed. On iOS the
    /// same sysctl is unavailable and `hw.machine` returns the *device* identifier — an
    /// iPhone 15 Pro reports `iPhone16,1`. Shown under a "Chip" heading that is wrong twice
    /// over: it is not a chip, and it reads as the name of a phone the owner does not have. A
    /// tester reported exactly that ("iPhone model shows incorrect this is a iPhone 15").
    ///
    /// So the identifier is translated. An identifier with no entry falls back to itself, which
    /// is no worse than before and keeps a device released after this build honest rather than
    /// guessed at.
    static var chipName: String {
        #if os(macOS)
        return sysctlString("machdep.cpu.brand_string") ?? "Apple silicon"
        #else
        guard let identifier = sysctlString("hw.machine") else { return UIDevice.current.model }
        return appleChips[identifier] ?? identifier
        #endif
    }

    #if os(iOS)
    /// Device identifier to the chip inside it, for everything that runs this app.
    ///
    /// The deployment target is iOS 26, which rules out anything older than the A13 devices, so
    /// the table starts there. Simulators report the host Mac's identifier and fall through to
    /// the raw string, which is correct — a Simulator has no iPhone chip in it.
    private static let appleChips: [String: String] = [
        // iPhone
        "iPhone12,1": "A13 Bionic", "iPhone12,3": "A13 Bionic", "iPhone12,5": "A13 Bionic",
        "iPhone12,8": "A13 Bionic",
        "iPhone13,1": "A14 Bionic", "iPhone13,2": "A14 Bionic", "iPhone13,3": "A14 Bionic",
        "iPhone13,4": "A14 Bionic",
        "iPhone14,2": "A15 Bionic", "iPhone14,3": "A15 Bionic", "iPhone14,4": "A15 Bionic",
        "iPhone14,5": "A15 Bionic", "iPhone14,6": "A15 Bionic", "iPhone14,7": "A15 Bionic",
        "iPhone14,8": "A15 Bionic",
        "iPhone15,2": "A16 Bionic", "iPhone15,3": "A16 Bionic",
        "iPhone15,4": "A16 Bionic", "iPhone15,5": "A16 Bionic",
        "iPhone16,1": "A17 Pro", "iPhone16,2": "A17 Pro",
        "iPhone17,1": "A18 Pro", "iPhone17,2": "A18 Pro",
        "iPhone17,3": "A18", "iPhone17,4": "A18", "iPhone17,5": "A18",
        "iPhone18,1": "A19 Pro", "iPhone18,2": "A19 Pro", "iPhone18,3": "A19", "iPhone18,4": "A19",
        // iPad
        "iPad11,6": "A13 Bionic", "iPad11,7": "A13 Bionic",
        "iPad12,1": "A13 Bionic", "iPad12,2": "A13 Bionic",
        "iPad13,1": "M1", "iPad13,2": "M1",
        "iPad13,4": "M1", "iPad13,5": "M1", "iPad13,6": "M1", "iPad13,7": "M1",
        "iPad13,8": "M1", "iPad13,9": "M1", "iPad13,10": "M1", "iPad13,11": "M1",
        "iPad13,16": "M1", "iPad13,17": "M1",
        "iPad13,18": "A14 Bionic", "iPad13,19": "A14 Bionic",
        "iPad14,1": "A15 Bionic", "iPad14,2": "A15 Bionic",
        "iPad14,3": "M2", "iPad14,4": "M2", "iPad14,5": "M2", "iPad14,6": "M2",
        "iPad14,8": "M2", "iPad14,9": "M2", "iPad14,10": "M2", "iPad14,11": "M2",
        "iPad15,3": "A16", "iPad15,4": "A16", "iPad15,5": "A16", "iPad15,6": "A16",
        "iPad15,7": "A17 Pro", "iPad15,8": "A17 Pro",
        "iPad16,1": "A17 Pro", "iPad16,2": "A17 Pro",
        "iPad16,3": "M4", "iPad16,4": "M4", "iPad16,5": "M4", "iPad16,6": "M4",
    ]
    #endif

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    static func freeDiskBytes(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    /// Largest parameter count that fits comfortably in the available memory at Q4, as a label.
    static func headroomLabel(availableBytes: UInt64) -> String {
        let gb = Double(availableBytes) / 1_000_000_000
        switch gb {
        case ..<2: return "room for a 1B model"
        case ..<3.5: return "room for a 3B at Q4"
        case ..<6: return "room for a 7B at Q4"
        case ..<10: return "room for a 8B at Q5"
        case ..<20: return "room for a 14B at Q4"
        default: return "room for a 32B at Q4"
        }
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
