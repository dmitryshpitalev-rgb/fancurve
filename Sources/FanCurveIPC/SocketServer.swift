import Foundation

/// Unix-domain stream server for newline-delimited messages. Each complete line (without its
/// newline) goes to `handler` on the server's queue; the returned bytes are written back.
/// The queue must be dedicated to this server — never the daemon's engine queue: a client that
/// stops reading can hold it for up to `sendTimeoutSeconds` before it is dropped.
public final class SocketServer {
    public static let maxRequestBytes = 1 << 20
    static let sendTimeoutSeconds = 2.0
    /// How long accepting stops after `accept` fails for a reason other than an empty backlog.
    static let acceptPauseSeconds = 1.0

    private final class Client {
        let fd: Int32
        var source: DispatchSourceRead?
        var buffer = Data()
        /// Kept between reads, so a read event allocates nothing for them.
        var chunk = [UInt8](repeating: 0, count: 65_536)

        init(fd: Int32) {
            self.fd = fd
        }
    }

    private let path: String
    private let queue: DispatchQueue
    private let handler: (Data) -> Data
    private var listenSource: DispatchSourceRead?
    private var clients: [Int32: Client] = [:]

    public init(path: String, queue: DispatchQueue, handler: @escaping (Data) -> Data) {
        self.path = path
        self.queue = queue
        self.handler = handler
    }

    /// A server released without `stop()` would leave its sources firing with nobody to accept or
    /// read: a waiting connection would make them spin.
    deinit {
        listenSource?.cancel()
        for client in clients.values {
            client.source?.cancel()
        }
    }

    /// Replaces a stale socket file, binds, applies `mode` and (if given) the group, starts accepting.
    public func start(mode: mode_t, groupID: gid_t? = nil) throws {
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.system(call: "socket", code: errno) }
        do {
            var address = try UnixSocket.address(path)
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bound == 0 else { throw SocketError.system(call: "bind", code: errno) }
            guard chmod(path, mode) == 0 else { throw SocketError.system(call: "chmod", code: errno) }
            if let groupID, chown(path, uid_t.max, groupID) != 0 {
                throw SocketError.system(call: "chown", code: errno)
            }
            guard listen(fd, 16) == 0 else { throw SocketError.system(call: "listen", code: errno) }
            // `acceptPending` accepts until the backlog is empty, which only a non-blocking socket reports.
            guard UnixSocket.setBlocking(fd, false) else { throw SocketError.system(call: "fcntl", code: errno) }
        } catch {
            close(fd)
            unlink(path)
            throw error
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPending(fd) }
        source.setCancelHandler { close(fd) }
        listenSource = source
        source.resume()
    }

    public func stop() {
        queue.sync {
            listenSource?.cancel()
            listenSource = nil
            for client in clients.values {
                client.source?.cancel()
            }
            clients.removeAll()
        }
        unlink(path)
    }

    private func acceptPending(_ listenFD: Int32) {
        while true {
            let fd = accept(listenFD, nil, nil)
            guard fd >= 0 else {
                let code = errno
                if code == EINTR || code == ECONNABORTED { continue }
                // Anything but an empty backlog (EMFILE, ENFILE) leaves the connection waiting, and the
                // source would fire again at once.
                if code != EAGAIN && code != EWOULDBLOCK { pauseAccepting() }
                return
            }
            // Accepted BSD sockets inherit O_NONBLOCK from the listener. Clients read once per event
            // and write with a timeout, so they are made blocking; a client whose socket refuses any of
            // this is closed rather than served without it.
            guard UnixSocket.setBlocking(fd, true), UnixSocket.noSigPipe(fd),
                  UnixSocket.setTimeout(fd, SO_SNDTIMEO, seconds: Self.sendTimeoutSeconds) else {
                close(fd)
                continue
            }
            let client = Client(fd: fd)
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in self?.readAvailable(client) }
            source.setCancelHandler { close(fd) }
            client.source = source
            clients[fd] = client
            source.resume()
        }
    }

    /// Resumes after `acceptPauseSeconds`, even when `stop` cancelled the source meanwhile: a
    /// suspended source never runs its cancel handler, which closes the socket.
    private func pauseAccepting() {
        guard let source = listenSource else { return }
        source.suspend()
        queue.asyncAfter(deadline: .now() + Self.acceptPauseSeconds) { source.resume() }
    }

    private func readAvailable(_ client: Client) {
        let count = client.chunk.withUnsafeMutableBytes { Darwin.read(client.fd, $0.baseAddress, $0.count) }
        if count < 0, errno == EINTR || errno == EAGAIN { return }
        guard count > 0 else {
            drop(client)
            return
        }
        // Only the new bytes can hold a newline: everything buffered before was scanned already, so a
        // long request costs one pass, not one pass per chunk.
        var unscanned = client.buffer.endIndex
        client.buffer.append(contentsOf: client.chunk[..<count])
        while let newline = client.buffer[unscanned...].firstIndex(of: 0x0A) {
            let line = Data(client.buffer[client.buffer.startIndex..<newline])
            client.buffer.removeSubrange(client.buffer.startIndex...newline)
            unscanned = client.buffer.startIndex
            guard UnixSocket.writeAll(client.fd, handler(line)) else {
                drop(client)
                return
            }
        }
        if client.buffer.count > Self.maxRequestBytes {
            drop(client)
        }
    }

    private func drop(_ client: Client) {
        client.source?.cancel()
        client.source = nil
        clients[client.fd] = nil
    }
}
