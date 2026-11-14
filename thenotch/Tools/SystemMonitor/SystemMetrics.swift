//
//  SystemMetrics.swift
//  thenotch
//

import Foundation

/// Pure math and formatting for the System Monitor, on plain values. The
/// system calls live in `SystemReader`.

/// What the menu bar shows.
enum SystemMetric: String, CaseIterable, Identifiable, Hashable {
    case cpu, memory, network

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .network: "Network"
        }
    }
}

/// How often the sampler reads while the popover is closed.
enum SystemMonitorInterval: Int, CaseIterable, Identifiable {
    case one = 1, two = 2, five = 5

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }
    var title: String { "\(rawValue) s" }
}

/// Cumulative CPU ticks (all cores together) since boot.
struct CPUTicks: Equatable {
    var user: UInt64
    var system: UInt64
    var idle: UInt64
    var nice: UInt64

    var total: UInt64 { user &+ system &+ idle &+ nice }
}

enum CPUUsage {
    /// Busy share (0...1) between two readings; `nil` without a delta or
    /// when a counter went backwards. The kernel's ticks are 32-bit and wrap
    /// after weeks of uptime; that one reading is skipped (nil), not wrong.
    static func fraction(previous: CPUTicks, current: CPUTicks) -> Double? {
        guard current.user >= previous.user, current.system >= previous.system,
              current.idle >= previous.idle, current.nice >= previous.nice
        else { return nil }
        let total = current.total - previous.total
        guard total > 0 else { return nil }
        let idle = current.idle - previous.idle
        return min(1, max(0, Double(total - idle) / Double(total)))
    }
}

struct MemoryUsage: Equatable {
    var used: UInt64
    var total: UInt64

    /// Activity Monitor's "Memory Used" is approximately app memory plus
    /// wired plus compressed; here: (active + wired + compressed) pages.
    static func from(
        activePages: UInt64,
        wiredPages: UInt64,
        compressedPages: UInt64,
        pageSize: UInt64,
        total: UInt64
    ) -> MemoryUsage {
        let used = (activePages &+ wiredPages &+ compressedPages) &* pageSize
        return MemoryUsage(used: min(used, total), total: total)
    }

    var fraction: Double {
        total > 0 ? Double(used) / Double(total) : 0
    }
}

enum NetworkRate {
    /// Bytes per second between two cumulative counters. A counter that went
    /// down (interface reset or removed) or a missing interval gives 0.
    static func bytesPerSecond(previous: UInt64, current: UInt64, elapsed: TimeInterval) -> Double {
        guard current >= previous, elapsed > 0 else { return 0 }
        return Double(current - previous) / elapsed
    }
}

/// Which network interfaces count towards the totals, and the walk over the
/// `NET_RT_IFLIST2` buffer.
enum NetworkInterfaces {
    /// Virtual, tunnel and peer-to-peer interfaces carry traffic that is
    /// already counted on the physical one (VPN) or isn't internet traffic.
    private static let excludedPrefixes = [
        "lo", "utun", "ipsec", "ppp", "awdl", "llw", "bridge", "ap", "gif", "stf", "anpi", "vmenet", "feth",
    ]

    /// Up, not loopback, and a physical interface (en*, pdp_ip*...).
    static func isCounted(name: String, flags: Int32) -> Bool {
        guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { return false }
        return !excludedPrefixes.contains { name.hasPrefix($0) }
    }

    /// Sums received and sent bytes of the counted interfaces in a
    /// `NET_RT_IFLIST2` buffer. `name` maps an interface index to its name.
    static func totals(buffer: UnsafeRawBufferPointer, name: (UInt16) -> String?) -> (received: UInt64, sent: UInt64) {
        var received: UInt64 = 0
        var sent: UInt64 = 0
        var offset = 0
        while offset + MemoryLayout<if_msghdr>.size <= buffer.count {
            let header = buffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
            let size = Int(header.ifm_msglen)
            guard size > 0 else { break }
            if Int32(header.ifm_type) == RTM_IFINFO2,
               offset + MemoryLayout<if_msghdr2>.size <= buffer.count {
                let message = buffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                if let interface = name(message.ifm_index),
                   isCounted(name: interface, flags: message.ifm_flags) {
                    received &+= message.ifm_data.ifi_ibytes
                    sent &+= message.ifm_data.ifi_obytes
                }
            }
            offset += size
        }
        return (received, sent)
    }
}

struct DiskUsage: Equatable {
    /// Available for important usage (what Finder reports as available).
    var available: UInt64
    var total: UInt64

    var used: UInt64 { total > available ? total - available : 0 }

    var fraction: Double {
        total > 0 ? Double(used) / Double(total) : 0
    }
}

enum MetricFormat {
    /// 0...1 as "12%".
    static func percent(_ fraction: Double) -> String {
        "\(Int((min(1, max(0, fraction)) * 100).rounded()))%"
    }

    /// "512 B/s", "1.2 MB/s" (decimal units, like Finder).
    static func rate(_ bytesPerSecond: Double) -> String {
        "\(bytes(bytesPerSecond))/s"
    }

    /// "120 GB", "1.2 TB".
    static func capacity(_ bytes: UInt64) -> String {
        Self.bytes(Double(bytes))
    }

    private static func bytes(_ value: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var scaled = max(0, value)
        var index = 0
        while scaled >= 999.5, index < units.count - 1 {
            scaled /= 1000
            index += 1
        }
        if index == 0 { return "\(Int(scaled.rounded())) B" }
        let text = scaled < 9.95 ? String(format: "%.1f", scaled) : String(format: "%.0f", scaled)
        return "\(text) \(units[index])"
    }
}
