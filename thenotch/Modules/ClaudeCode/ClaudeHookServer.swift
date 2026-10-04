//
//  ClaudeHookServer.swift
//  thenotch
//

import Darwin
import Foundation
import os

/// Receives Claude Code's hook calls: a Unix domain socket that each hook
/// command connects to, writes its JSON input to, and closes
/// (`ClaudeHooksConfig`). Only this user can connect (the socket is 0600).
/// Connections are read on a background queue; events are delivered on
/// the main queue.
final class ClaudeHookServer: @unchecked Sendable {
    /// `~/Library/Application Support/<bundle id>/claude-hooks.sock`.
    static var defaultPath: String {
        URL.applicationSupportDirectory
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "thenotch", isDirectory: true)
            .appendingPathComponent("claude-hooks.sock")
            .path
    }

    let path: String
    private let onEvent: @MainActor (ClaudeHookEvent) -> Void
    private let queue = DispatchQueue(label: "me.kitkas1412.thenotch.claude-hooks")
    /// Touched only on `queue`.
    private var listener: Int32 = -1
    private var source: DispatchSourceRead?

    init(path: String = ClaudeHookServer.defaultPath, onEvent: @escaping @MainActor (ClaudeHookEvent) -> Void) {
        self.path = path
        self.onEvent = onEvent
    }

    enum ServerError: Error {
        case pathTooLong
        case socket(Int32)
    }

    func start() throws {
        try queue.sync {
            guard listener < 0 else { return }
            try FileManager.default.createDirectory(
                atPath: (path as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            let fd = try Self.listen(at: path)
            listener = fd
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in
                self?.acceptAll()
            }
            source.setCancelHandler {
                close(fd)
            }
            self.source = source
            source.resume()
        }
    }

    func stop() {
        queue.sync {
            source?.cancel()
            source = nil
            listener = -1
            unlink(path)
        }
    }

    deinit {
        source?.cancel()
    }

    // MARK: - On `queue`

    private func acceptAll() {
        while true {
            let client = accept(listener, nil, nil)
            guard client >= 0 else { return }  // EAGAIN: none left
            let data = Self.readAll(client)
            close(client)
            if let data, let event = ClaudeHookEvent.parse(data) {
                DispatchQueue.main.async { [onEvent] in
                    MainActor.assumeIsolated {
                        onEvent(event)
                    }
                }
            }
        }
    }

    /// Reads until the hook closes its end, giving up after a second or
    /// past `ClaudeHookEvent.maxPayloadSize`.
    private static func readAll(_ client: Int32) -> Data? {
        // Accepted sockets inherit the listener's non-blocking mode.
        _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = read(client, &buffer, buffer.count)
            if count == 0 { return data }
            guard count > 0 else { return nil }
            data.append(buffer, count: count)
            if data.count > ClaudeHookEvent.maxPayloadSize { return nil }
        }
    }

    private static func listen(at path: String) throws -> Int32 {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else { throw ServerError.pathTooLong }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: Array(path.utf8) + [0])
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ServerError.socket(errno) }
        // A socket file left by a previous run.
        unlink(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, chmod(path, 0o600) == 0, Darwin.listen(fd, 16) == 0 else {
            let error = errno
            close(fd)
            throw ServerError.socket(error)
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        return fd
    }
}
