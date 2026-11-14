import Darwin
import Foundation
import Testing
@testable import thenotch

struct NetworkInterfaceFilterTests {
    @Test func countsPhysicalInterfacesThatAreUp() {
        #expect(NetworkInterfaces.isCounted(name: "en0", flags: IFF_UP))
        #expect(NetworkInterfaces.isCounted(name: "pdp_ip0", flags: IFF_UP))
    }

    @Test func skipsInterfacesThatAreDownOrLoopback() {
        #expect(!NetworkInterfaces.isCounted(name: "en0", flags: 0))
        #expect(!NetworkInterfaces.isCounted(name: "en0", flags: IFF_UP | IFF_LOOPBACK))
        #expect(!NetworkInterfaces.isCounted(name: "lo0", flags: IFF_UP))
    }

    @Test func skipsVirtualAndPeerToPeerInterfaces() {
        for name in ["utun3", "ipsec0", "ppp0", "awdl0", "llw0", "bridge100", "ap1", "gif0", "stf0", "anpi0", "vmenet0", "feth0"] {
            #expect(!NetworkInterfaces.isCounted(name: name, flags: IFF_UP), "\(name)")
        }
    }

    private func message(index: UInt16, flags: Int32, received: UInt64, sent: UInt64) -> [UInt8] {
        var header = if_msghdr2()
        header.ifm_msglen = UInt16(MemoryLayout<if_msghdr2>.size)
        header.ifm_type = UInt8(RTM_IFINFO2)
        header.ifm_index = index
        header.ifm_flags = flags
        header.ifm_data.ifi_ibytes = received
        header.ifm_data.ifi_obytes = sent
        return withUnsafeBytes(of: &header) { Array($0) }
    }

    @Test func totalsSumOnlyCountedInterfaces() {
        let names: [UInt16: String] = [1: "lo0", 2: "en0", 3: "utun2", 4: "en1"]
        var buffer: [UInt8] = []
        buffer += message(index: 1, flags: IFF_UP | IFF_LOOPBACK, received: 1000, sent: 1000)
        buffer += message(index: 2, flags: IFF_UP, received: 100, sent: 10)
        buffer += message(index: 3, flags: IFF_UP, received: 500, sent: 500)
        buffer += message(index: 4, flags: IFF_UP, received: 200, sent: 20)
        buffer += message(index: 9, flags: IFF_UP, received: 700, sent: 700) // unknown index
        let totals = buffer.withUnsafeBytes { NetworkInterfaces.totals(buffer: $0) { names[$0] } }
        #expect(totals.received == 300)
        #expect(totals.sent == 30)
    }

    @Test func totalsOfEmptyOrTruncatedBufferAreZero() {
        let empty = NetworkInterfaces.totals(buffer: UnsafeRawBufferPointer(start: nil, count: 0)) { _ in "en0" }
        #expect(empty.received == 0 && empty.sent == 0)
        let truncated = Array(message(index: 2, flags: IFF_UP, received: 5, sent: 5).prefix(20))
        let result = truncated.withUnsafeBytes { NetworkInterfaces.totals(buffer: $0) { _ in "en0" } }
        #expect(result.received == 0)
    }
}
