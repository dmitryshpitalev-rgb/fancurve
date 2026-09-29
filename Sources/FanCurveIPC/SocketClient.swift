import Foundation

/// Blocking client: one connection, one request line and one reply line at a time.
final class SocketClient {
    static let maxResponseBytes = 8 << 20

    private let fd: Int32
    private var pending = Data()
    /// Kept between reads, so an exchange allocates nothing for them.
    private var chunk = [UInt8](repeating: 0, count: 65_536)

    /// `timeout` bounds every write and every wait for reply bytes.
    init(path: String, timeout: Double) throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.system(call: "socket", code: errno) }
        do {
            var address = try UnixSocket.address(path)
            let connected = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard connected == 0 else { throw SocketError.system(call: "connect", code: errno) }
            // All three must hold: without the timeouts a daemon that stops answering would block
            // the caller for good.
            guard UnixSocket.noSigPipe(fd), UnixSocket.setTimeout(fd, SO_SNDTIMEO, seconds: timeout),
                  UnixSocket.setTimeout(fd, SO_RCVTIMEO, seconds: timeout) else {
                throw SocketError.system(call: "setsockopt", code: errno)
            }
        } catch {
            close(fd)
            throw error
        }
        self.fd = fd
    }

    deinit {
        close(fd)
    }

    /// Sends one line (a newline is added if missing) and returns the reply line without its newline.
    /// A failure shuts the connection: a half-sent request or an unread reply would put every later
    /// reply out of step with its request.
    func exchange(_ line: Data) throws -> Data {
        do { return try roundTrip(line) } catch { shutdown(fd, SHUT_RDWR); throw error }
    }

    private func roundTrip(_ line: Data) throws -> Data {
        var message = line
        if message.last != 0x0A { message.append(0x0A) }
        guard UnixSocket.writeAll(fd, message) else { throw SocketError.system(call: "write", code: errno) }
        var scanned = 0
        while true {
            // Only the bytes that arrived since the last look can hold the newline.
            if let newline = pending[(pending.startIndex + scanned)...].firstIndex(of: 0x0A) {
                let reply = Data(pending[pending.startIndex..<newline])
                pending.removeSubrange(pending.startIndex...newline)
                return reply
            }
            scanned = pending.count
            guard pending.count <= Self.maxResponseBytes else { throw SocketError.lineTooLong }
            let count = chunk.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count < 0 {
                let code = errno
                if code == EINTR { continue }
                // SO_RCVTIMEO ran out before the whole reply arrived.
                if code == EAGAIN || code == EWOULDBLOCK { throw SocketError.timedOut }
                throw SocketError.system(call: "read", code: code)
            }
            guard count > 0 else { throw SocketError.closed }
            pending.append(contentsOf: chunk[..<count])
        }
    }
}
