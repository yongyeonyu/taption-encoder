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

enum EncodingRuntimeWarningSeverity: String, Equatable {
    case notice
    case warning
    case critical
}

struct EncodingRuntimeWarning: Equatable, Identifiable {
    enum Kind: String, Equatable {
        case thermal
        case memory
        case battery
        case runtime
    }

    var kind: Kind
    var severity: EncodingRuntimeWarningSeverity
    var title: String
    var message: String

    var id: String {
        "\(kind.rawValue)-\(severity.rawValue)-\(title)"
    }
}

struct EncodingRuntimePowerSnapshot: Equatable {
    var batteryPercent: Int?
    var isPowerConnected: Bool
    var isPowerStateKnown: Bool
}

struct EncodingResourceUsageSnapshot: Equatable {
    var timestamp: Date
    var cpuCores: [EncodingCPUCoreUsage]
    var appMemoryBytes: UInt64?
    var totalPhysicalMemoryBytes: UInt64
    var thermalState: ProcessInfo.ThermalState
    var runtimeWarnings: [EncodingRuntimeWarning]

    init(
        timestamp: Date,
        cpuCores: [EncodingCPUCoreUsage],
        appMemoryBytes: UInt64?,
        totalPhysicalMemoryBytes: UInt64,
        thermalState: ProcessInfo.ThermalState = .nominal,
        runtimeWarnings: [EncodingRuntimeWarning] = []
    ) {
        self.timestamp = timestamp
        self.cpuCores = cpuCores
        self.appMemoryBytes = appMemoryBytes
        self.totalPhysicalMemoryBytes = totalPhysicalMemoryBytes
        self.thermalState = thermalState
        self.runtimeWarnings = runtimeWarnings
    }

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

enum EncodingRuntimeWarningEvaluator {
    static func warnings(
        resourceUsage: EncodingResourceUsageSnapshot,
        powerSnapshot: EncodingRuntimePowerSnapshot? = nil,
        batteryLimitPercent: Int = 30,
        estimatedRemainingTime: TimeInterval? = nil,
        optimizationProfile: TaptionEncodingOptimizationProfile = .balanced
    ) -> [EncodingRuntimeWarning] {
        var warnings: [EncodingRuntimeWarning] = []
        appendThermalWarning(resourceUsage.thermalState, optimizationProfile: optimizationProfile, to: &warnings)
        appendMemoryWarning(resourceUsage.memoryPercent, to: &warnings)
        appendBatteryWarning(
            powerSnapshot,
            batteryLimitPercent: batteryLimitPercent,
            estimatedRemainingTime: estimatedRemainingTime,
            to: &warnings
        )
        appendRuntimeWarning(
            estimatedRemainingTime,
            powerSnapshot: powerSnapshot,
            optimizationProfile: optimizationProfile,
            to: &warnings
        )
        return warnings
    }

    private static func appendThermalWarning(
        _ thermalState: ProcessInfo.ThermalState,
        optimizationProfile: TaptionEncodingOptimizationProfile,
        to warnings: inout [EncodingRuntimeWarning]
    ) {
        switch thermalState {
        case .critical:
            warnings.append(EncodingRuntimeWarning(
                kind: .thermal,
                severity: .critical,
                title: "Thermal Pressure Critical",
                message: "The device is too hot. Pause encoding, cool the device, or switch to Battery Saver before continuing."
            ))
        case .serious:
            warnings.append(EncodingRuntimeWarning(
                kind: .thermal,
                severity: .warning,
                title: "Device Getting Hot",
                message: "iOS reports serious thermal pressure. Long encodes may slow down, especially on older devices."
            ))
        case .fair where optimizationProfile == .performance:
            warnings.append(EncodingRuntimeWarning(
                kind: .thermal,
                severity: .notice,
                title: "Device Warming Up",
                message: "Max Performance can raise heat during long encodes. Battery Saver lowers the load if the device keeps warming."
            ))
        default:
            break
        }
    }

    private static func appendMemoryWarning(
        _ memoryPercent: Double?,
        to warnings: inout [EncodingRuntimeWarning]
    ) {
        guard let memoryPercent else {
            return
        }
        if memoryPercent >= 90 {
            warnings.append(EncodingRuntimeWarning(
                kind: .memory,
                severity: .critical,
                title: "App Memory Very High",
                message: "Taption Encoder is using most available memory. Close other apps or reduce the batch before starting another long encode."
            ))
        } else if memoryPercent >= 75 {
            warnings.append(EncodingRuntimeWarning(
                kind: .memory,
                severity: .warning,
                title: "App Memory High",
                message: "Memory use is high. Older devices may pause or terminate long encodes if memory keeps rising."
            ))
        }
    }

    private static func appendBatteryWarning(
        _ powerSnapshot: EncodingRuntimePowerSnapshot?,
        batteryLimitPercent: Int,
        estimatedRemainingTime: TimeInterval?,
        to warnings: inout [EncodingRuntimeWarning]
    ) {
        guard let powerSnapshot,
              powerSnapshot.isPowerStateKnown,
              !powerSnapshot.isPowerConnected,
              let batteryPercent = powerSnapshot.batteryPercent else {
            return
        }

        if batteryPercent <= batteryLimitPercent {
            warnings.append(EncodingRuntimeWarning(
                kind: .battery,
                severity: .critical,
                title: "Battery Limit Reached",
                message: "Battery is at \(batteryPercent)%. Connect power so the next encode can continue safely."
            ))
            return
        }

        let nearLimitThreshold = min(100, batteryLimitPercent + 10)
        if batteryPercent <= nearLimitThreshold {
            warnings.append(EncodingRuntimeWarning(
                kind: .battery,
                severity: .warning,
                title: "Battery Near Limit",
                message: "Battery is at \(batteryPercent)%. Connect power before starting another encode."
            ))
        } else if let estimatedRemainingTime,
                  estimatedRemainingTime >= 20 * 60,
                  batteryPercent <= 40 {
            warnings.append(EncodingRuntimeWarning(
                kind: .battery,
                severity: .warning,
                title: "Battery May Not Last",
                message: "This encode has about \(formattedDuration(estimatedRemainingTime)) remaining on \(batteryPercent)% battery."
            ))
        }
    }

    private static func appendRuntimeWarning(
        _ estimatedRemainingTime: TimeInterval?,
        powerSnapshot: EncodingRuntimePowerSnapshot?,
        optimizationProfile: TaptionEncodingOptimizationProfile,
        to warnings: inout [EncodingRuntimeWarning]
    ) {
        guard let estimatedRemainingTime,
              estimatedRemainingTime >= 30 * 60 else {
            return
        }
        let connected = powerSnapshot?.isPowerConnected == true
        let profileHint = optimizationProfile == .batterySaver
            ? "Keep the app open and plugged in for best reliability."
            : "Battery Saver can reduce heat and battery drain for this kind of encode."
        warnings.append(EncodingRuntimeWarning(
            kind: .runtime,
            severity: connected ? .notice : .warning,
            title: "Long Runtime Estimate",
            message: "About \(formattedDuration(estimatedRemainingTime)) remaining. \(profileHint)"
        ))
    }

    private static func formattedDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(1, Int((seconds / 60).rounded()))
        guard totalMinutes >= 60 else {
            return "\(totalMinutes)m"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
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

        var snapshot = EncodingResourceUsageSnapshot(
            timestamp: Date(),
            cpuCores: cpuCores,
            appMemoryBytes: Self.currentAppMemoryBytes(),
            totalPhysicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            thermalState: ProcessInfo.processInfo.thermalState
        )
        snapshot.runtimeWarnings = EncodingRuntimeWarningEvaluator.warnings(resourceUsage: snapshot)
        return snapshot
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
