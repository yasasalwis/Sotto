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

    static var chipName: String {
        #if os(macOS)
        return sysctlString("machdep.cpu.brand_string") ?? "Apple silicon"
        #else
        return sysctlString("hw.machine") ?? UIDevice.current.model
        #endif
    }

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
