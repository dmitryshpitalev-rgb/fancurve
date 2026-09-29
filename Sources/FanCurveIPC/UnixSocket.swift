import Foundation

public enum SocketError: Error, Equatable, CustomStringConvertible {
    case pathTooLong(String)
    case system(call: String, code: Int32)
    case closed
    case lineTooLong
    /// No reply within the connection's timeout.
    case timedOut

    public var description: String {
        switch self {
        case .pathTooLong(let path): return "socket path too long: \(path)"
        case .system(let call, let code): return "\(call) failed: \(String(cString: strerror(code)))"
        case .closed: return "the connection closed before a full reply arrived"
        case .lineTooLong: return "the reply exceeds the size limit"
        case .timedOut: return "no reply within the timeout"
        }
    }
}

/// Socket calls shared by the client and the server. The option setters return false when the
/// option did not take; `errno` then says why.
enum UnixSocket {
    static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { throw SocketError.pathTooLong(path) }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        return address
    }

    static func setTimeout(_ fd: Int32, _ option: Int32, seconds: Double) -> Bool {
        var value = timeval(tv_sec: Int(seconds), tv_usec: Int32((seconds - Double(Int(seconds))) * 1_000_000))
        return setsockopt(fd, SOL_SOCKET, option, &value, socklen_t(MemoryLayout<timeval>.size)) == 0
    }

    static func setBlocking(_ fd: Int32, _ blocking: Bool) -> Bool {
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0 else { return false }
        return fcntl(fd, F_SETFL, blocking ? flags & ~O_NONBLOCK : flags | O_NONBLOCK) == 0
    }

    /// A write to a closed peer returns EPIPE instead of killing the process with SIGPIPE.
    static func noSigPipe(_ fd: Int32) -> Bool {
        var on: Int32 = 1
        return setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size)) == 0
    }

    /// Writes everything or fails; the descriptor is blocking with a send timeout.
    static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return true }
            var offset = 0
            while offset < raw.count {
                let written = Darwin.write(fd, base + offset, raw.count - offset)
                if written > 0 {
                    offset += written
                    continue
                }
                if written < 0, errno == EINTR { continue }
                return false
            }
            return true
        }
    }
}
