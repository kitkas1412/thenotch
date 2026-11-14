//
//  SystemReader.swift
//  thenotch
//

import Darwin
import Foundation

/// One reading of the system.
struct SystemSnapshot: Equatable {
    var cpu: Double = 0
    var memory = MemoryUsage(used: 0, total: ProcessInfo.processInfo.physicalMemory)
    /// Bytes per second.
    var networkDown: Double = 0
    var networkUp: Double = 0
    var disk = DiskUsage(available: 0, total: 0)
}

/// Thin wrappers over the system calls; no state.
enum SystemCalls {
    static func cpuTicks(host: mach_port_t) -> CPUTicks? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUTicks(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
    }

    static func memory(host: mach_port_t) -> MemoryUsage? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return MemoryUsage.from(
            activePages: UInt64(stats.active_count),
            wiredPages: UInt64(stats.wire_count),
            compressedPages: UInt64(stats.compressor_page_count),
            pageSize: UInt64(getpagesize()),
            total: ProcessInfo.processInfo.physicalMemory
        )
    }

    /// Cumulative bytes received and sent by the physical interfaces.
    static func networkBytes() -> (received: UInt64, sent: UInt64)? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return nil }
        // Interfaces may appear between the two calls: leave some room.
        length += length / 10
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return nil }

        return buffer.withUnsafeBytes { raw in
            NetworkInterfaces.totals(buffer: UnsafeRawBufferPointer(rebasing: raw.prefix(length))) { index in
                var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                return if_indextoname(UInt32(index), &name).map { String(cString: $0) }
            }
        }
    }

    static func disk() -> DiskUsage? {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let available = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity
        else { return nil }
        return DiskUsage(available: UInt64(max(0, available)), total: UInt64(max(0, total)))
    }
}

/// Keeps the previous readings so rates can be computed. An actor, so the
/// reads run off the main thread.
actor SystemReader {
    private let host = mach_host_self()
    private var previousTicks: CPUTicks?
    private var previousNetwork: (received: UInt64, sent: UInt64)?
    private var previousTime: TimeInterval?
    private var last = SystemSnapshot()

    deinit {
        mach_port_deallocate(mach_task_self_, host)
    }

    /// Forget the previous readings (after a pause), so no rate spans it.
    func reset() {
        previousTicks = nil
        previousNetwork = nil
        previousTime = nil
    }

    func read() -> SystemSnapshot {
        let now = ProcessInfo.processInfo.systemUptime
        var snapshot = last

        if let ticks = SystemCalls.cpuTicks(host: host) {
            if let previousTicks, let fraction = CPUUsage.fraction(previous: previousTicks, current: ticks) {
                snapshot.cpu = fraction
            }
            previousTicks = ticks
        }

        if let memory = SystemCalls.memory(host: host) {
            snapshot.memory = memory
        }

        if let network = SystemCalls.networkBytes() {
            if let previousNetwork, let previousTime {
                let elapsed = now - previousTime
                snapshot.networkDown = NetworkRate.bytesPerSecond(previous: previousNetwork.received, current: network.received, elapsed: elapsed)
                snapshot.networkUp = NetworkRate.bytesPerSecond(previous: previousNetwork.sent, current: network.sent, elapsed: elapsed)
            } else {
                snapshot.networkDown = 0
                snapshot.networkUp = 0
            }
            previousNetwork = network
        }
        previousTime = now

        if let disk = SystemCalls.disk() {
            snapshot.disk = disk
        }

        last = snapshot
        return snapshot
    }
}
