import Darwin
import Foundation

struct EncodingCPUCoreUsage: Equatable, Identifiable {
    var index: Int
    var percent: Double

    var id: Int { index }

    init(index: Int, percent: Double) {
        self.index = index
        self.percent = min(max(percent, 0), 100)
    }

    var fraction: Double {
        percent / 100
    }

    var percentText: String {
        "\(Int(percent.rounded()))%"
    }
}

struct EncodingResourceUsageSnapshot: Equatable {
    var timestamp: Date
    var cpuCores: [EncodingCPUCoreUsage]
    var appMemoryBytes: UInt64?
    var totalPhysicalMemoryBytes: UInt64

    var memoryPercent: Double? {
        guard let appMemoryBytes,
              totalPhysicalMemoryBytes > 0 else {
            return nil
        }
        let percent = (Double(appMemoryBytes) / Double(totalPhysicalMemoryBytes)) * 100
        return min(max(percent, 0), 100)
    }

    var memoryPercentText: String {
        guard let memoryPercent else {
            return "--"
        }
        return "\(Int(memoryPercent.rounded()))%"
    }

    var memoryUsageText: String {
        guard let appMemoryBytes else {
            return "Memory unavailable"
        }
        return "\(Self.formattedBytes(appMemoryBytes)) / \(Self.formattedBytes(totalPhysicalMemoryBytes))"
    }

    static func formattedBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowedUnits = bytes >= 1_000_000_000 ? [.useGB] : [.useMB]
        formatter.includesUnit = true
        formatter.includesCount = true
        let cappedBytes = min(bytes, UInt64(Int64.max))
        return formatter.string(fromByteCount: Int64(cappedBytes))
    }
}

protocol EncodingResourceMonitoring: AnyObject {
    func sample() -> EncodingResourceUsageSnapshot
}

struct EncodingCPUCoreTicks: Equatable {
    var user: UInt64
    var system: UInt64
    var idle: UInt64
    var nice: UInt64

    var total: UInt64 {
        user + system + idle + nice
    }

    var active: UInt64 {
        user + system + nice
    }
}

enum EncodingResourceMonitorMath {
    static func cpuUsages(
        previous: [EncodingCPUCoreTicks],
        current: [EncodingCPUCoreTicks]
    ) -> [EncodingCPUCoreUsage] {
        current.enumerated().map { index, currentTicks in
            let percent: Double
            if previous.indices.contains(index) {
                percent = usagePercent(
                    previous: previous[index],
                    current: currentTicks
                )
            } else {
                percent = usagePercentSinceBoot(currentTicks)
            }
            return EncodingCPUCoreUsage(index: index, percent: percent)
        }
    }

    static func usagePercent(
        previous: EncodingCPUCoreTicks,
        current: EncodingCPUCoreTicks
    ) -> Double {
        let totalDelta = current.total >= previous.total
            ? current.total - previous.total
            : current.total
        guard totalDelta > 0 else {
            return 0
        }

        let activeDelta = current.active >= previous.active
            ? current.active - previous.active
            : current.active
        return min(max((Double(activeDelta) / Double(totalDelta)) * 100, 0), 100)
    }

    static func usagePercentSinceBoot(_ ticks: EncodingCPUCoreTicks) -> Double {
        guard ticks.total > 0 else {
            return 0
        }
        return min(max((Double(ticks.active) / Double(ticks.total)) * 100, 0), 100)
    }
}

final class SystemEncodingResourceMonitor: EncodingResourceMonitoring {
    private let lock = NSLock()
    private var previousTicks: [EncodingCPUCoreTicks] = []

    func sample() -> EncodingResourceUsageSnapshot {
        lock.lock()
        defer {
            lock.unlock()
        }

        let currentTicks = Self.readCPUTicks()
        let cpuCores = EncodingResourceMonitorMath.cpuUsages(
            previous: previousTicks,
            current: currentTicks
        )
        previousTicks = currentTicks

        return EncodingResourceUsageSnapshot(
            timestamp: Date(),
            cpuCores: cpuCores,
            appMemoryBytes: Self.currentAppMemoryBytes(),
            totalPhysicalMemoryBytes: ProcessInfo.processInfo.physicalMemory
        )
    }

    private static func readCPUTicks() -> [EncodingCPUCoreTicks] {
        var processorCount: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            processor_flavor_t(PROCESSOR_CPU_LOAD_INFO),
            &processorCount,
            &cpuInfo,
            &infoCount
        )

        guard result == KERN_SUCCESS,
              let cpuInfo else {
            return []
        }

        defer {
            let byteCount = vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: cpuInfo)),
                byteCount
            )
        }

        let stride = Int(CPU_STATE_MAX)
        return (0..<Int(processorCount)).map { index in
            let offset = index * stride
            return EncodingCPUCoreTicks(
                user: unsignedTick(cpuInfo[offset + Int(CPU_STATE_USER)]),
                system: unsignedTick(cpuInfo[offset + Int(CPU_STATE_SYSTEM)]),
                idle: unsignedTick(cpuInfo[offset + Int(CPU_STATE_IDLE)]),
                nice: unsignedTick(cpuInfo[offset + Int(CPU_STATE_NICE)])
            )
        }
    }

    private static func currentAppMemoryBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<natural_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    reboundPointer,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }
        return UInt64(info.phys_footprint)
    }

    private static func unsignedTick(_ tick: integer_t) -> UInt64 {
        UInt64(max(0, Int64(tick)))
    }
}
