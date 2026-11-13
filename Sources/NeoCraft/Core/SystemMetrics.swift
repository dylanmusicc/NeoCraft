import Darwin
import Foundation
import IOKit.ps

struct SystemSnapshot: Sendable {
    var totalMemory: UInt64
    var usedMemory: UInt64
    var availableMemory: UInt64
    var swapUsed: UInt64
    var cpuUsage: Double
    var thermalState: ProcessInfo.ThermalState
    var lowPowerMode: Bool
    var onACPower: Bool
    var batteryPercent: Int?
    var hardwareModel: String
    var chipName: String
    var osVersion: String

    static let placeholder = SystemSnapshot(
        totalMemory: ProcessInfo.processInfo.physicalMemory,
        usedMemory: 0,
        availableMemory: ProcessInfo.processInfo.physicalMemory,
        swapUsed: 0,
        cpuUsage: 0,
        thermalState: .nominal,
        lowPowerMode: false,
        onACPower: true,
        batteryPercent: nil,
        hardwareModel: "Mac",
        chipName: "Apple Silicon",
        osVersion: ProcessInfo.processInfo.operatingSystemVersionString
    )

    var memoryFraction: Double {
        guard totalMemory > 0 else { return 0 }
        return min(1, Double(usedMemory) / Double(totalMemory))
    }
}

@MainActor
final class SystemMetricsProvider {
    private var lastCPUInfo: host_cpu_load_info?
    private var lastCPUTime = Date.distantPast

    func sample() -> SystemSnapshot {
        let processInfo = ProcessInfo.processInfo
        let total = processInfo.physicalMemory
        let used = Self.usedMemory()
        let swap = Self.swapUsed()
        let cpu = cpuUsage()
        let power = Self.powerSource()
        return SystemSnapshot(
            totalMemory: total,
            usedMemory: used,
            availableMemory: total > used ? total - used : 0,
            swapUsed: swap,
            cpuUsage: cpu,
            thermalState: processInfo.thermalState,
            lowPowerMode: processInfo.isLowPowerModeEnabled,
            onACPower: power.onAC,
            batteryPercent: power.percent,
            hardwareModel: Self.sysctlString("hw.model") ?? "Mac",
            chipName: Self.sysctlString("machdep.cpu.brand_string")
                ?? Self.sysctlString("hw.chipname")
                ?? "Apple Silicon",
            osVersion: "\(processInfo.operatingSystemVersion.majorVersion).\(processInfo.operatingSystemVersion.minorVersion).\(processInfo.operatingSystemVersion.patchVersion)"
        )
    }

    private static func usedMemory() -> UInt64 {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return 0
        }
        let pageSize = UInt64(getpagesize())
        let usedPages = UInt64(statistics.active_count)
            + UInt64(statistics.wire_count)
            + UInt64(statistics.compressor_page_count)
        return usedPages * pageSize
    }

    private static func swapUsed() -> UInt64 {
        struct SwapUsage {
            var total: UInt64 = 0
            var available: UInt64 = 0
            var used: UInt64 = 0
            var pageSize: UInt32 = 0
            var encrypted: Int32 = 0
        }
        var usage = SwapUsage()
        var size = MemoryLayout<SwapUsage>.size
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            sysctlbyname("vm.swapusage", pointer, &size, nil, 0)
        }
        return result == 0 ? usage.used : 0
    }

    /// Whether the Mac is on AC power and the current battery charge, via IOKit.
    /// Uses raw CF APIs only — the Swift `as?` toll-free bridges around
    /// IOPSCopyPowerSourcesList/GetPowerSourceDescription corrupt the heap.
    private static func powerSource() -> (onAC: Bool, percent: Int?) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return (true, nil)
        }

        // Borrowed reference owned by `info` — must NOT be retained/released.
        var onAC = true
        if let type = IOPSGetProvidingPowerSourceType(info)?
            .takeUnretainedValue() as? String {
            onAC = type == kIOPSACPowerValue
        }

        var percent: Int?
        guard let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() else {
            return (onAC, percent)
        }

        let count = CFArrayGetCount(list)
        for index in 0..<count {
            guard let pointer = CFArrayGetValueAtIndex(list, index) else { continue }
            let source = unsafeBitCast(pointer, to: CFTypeRef.self)
            // The per-source dictionary is owned by `info` — borrowed, so
            // takeUnretainedValue is required (takeRetainedValue over-releases).
            guard let cfDescription = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() else { continue }
            guard let description = cfDescription as? [String: Any] else { continue }

            guard let type = description[kIOPSTypeKey] as? String,
                  type == kIOPSInternalBatteryType else { continue }
            let current = (description[kIOPSCurrentCapacityKey] as? Double) ?? 0
            let maxCapacity = (description[kIOPSMaxCapacityKey] as? Double) ?? 0
            if maxCapacity > 0 {
                percent = Int((current / maxCapacity * 100).rounded())
            }
        }
        return (onAC, percent)
    }

    private func cpuUsage() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        defer {
            lastCPUInfo = info
            lastCPUTime = Date()
        }
        guard let previous = lastCPUInfo else { return 0 }

        let user = Double(info.cpu_ticks.0 &- previous.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1 &- previous.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2 &- previous.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3 &- previous.cpu_ticks.3)
        let total = user + system + idle + nice
        guard total > 0 else { return 0 }
        return min(1, max(0, (user + system + nice) / total))
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        let result = buffer.withUnsafeMutableBytes { raw in
            sysctlbyname(name, raw.baseAddress, &size, nil, 0)
        }
        guard result == 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let value = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

extension ProcessInfo.ThermalState {
    var displayName: String {
        switch self {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }
}
