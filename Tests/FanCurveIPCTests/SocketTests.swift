import Foundation
import Testing
@testable import FanCurveIPC

/// Short /tmp path: a unix socket path must fit in 104 bytes.
func tempSocketPath() -> String {
    "/tmp/fc-ipc-\(getpid())-\(UInt32.random(in: 0...UInt32.max)).sock"
}

/// Answers every line with "echo:" and the line.
func startEchoServer(at path: String, label: String) throws -> SocketServer {
    let server = SocketServer(path: path, queue: DispatchQueue(label: label)) { line in
        Data("echo:".utf8) + line + Data([0x0A])
    }
    try server.start(mode: 0o600)
    return server
}

/// A bare connection for writes SocketClient never makes: several lines at once, or no newline.
func rawConnection(to path: String) throws -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    var address = try UnixSocket.address(path)
    let connected = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard connected == 0, UnixSocket.noSigPipe(fd), UnixSocket.setTimeout(fd, SO_RCVTIMEO, seconds: 3) else {
        let code = errno
        close(fd)
        throw SocketError.system(call: "connect", code: code)
    }
    return fd
}

/// What arrives until `lines` newlines are in, the peer closes, or 3 s pass in silence.
func receive(_ fd: Int32, lines: Int) -> String {
    var received: [UInt8] = []
    var chunk = [UInt8](repeating: 0, count: 4096)
    while received.filter({ $0 == 0x0A }).count < lines {
        let count = read(fd, &chunk, chunk.count)
        guard count > 0 else { break }
        received += chunk[..<count]
    }
    return String(decoding: received, as: UTF8.self)
}

@Suite struct SocketTests {
    @Test func linesGoBothWaysIncludingABigReply() throws {
        let path = tempSocketPath()
        let server = SocketServer(path: path, queue: DispatchQueue(label: "test.server")) { line in
            if line == Data("big".utf8) {
                return Data(repeating: 0x61, count: 2_000_000) + Data([0x0A])
            }
            return Data("echo:".utf8) + line + Data([0x0A])
        }
        try server.start(mode: 0o660)
        defer { server.stop() }
        var info = stat()
        #expect(stat(path, &info) == 0)
        #expect(info.st_mode & 0o777 == 0o660)
        let client = try SocketClient(path: path, timeout: 3)
        #expect(try client.exchange(Data("hello".utf8)) == Data("echo:hello".utf8))
        #expect(try client.exchange(Data("again\n".utf8)) == Data("echo:again".utf8))
        #expect(try client.exchange(Data("big".utf8)).count == 2_000_000)
        let second = try SocketClient(path: path, timeout: 3)
        #expect(try second.exchange(Data("two".utf8)) == Data("echo:two".utf8))
    }

    @Test func aStaleSocketFileIsReplaced() throws {
        let path = tempSocketPath()
        FileManager.default.createFile(atPath: path, contents: Data("stale".utf8))
        let server = SocketServer(path: path, queue: DispatchQueue(label: "test.stale")) { _ in Data("ok\n".utf8) }
        try server.start(mode: 0o600)
        defer { server.stop() }
        #expect(try SocketClient(path: path, timeout: 3).exchange(Data("x".utf8)) == Data("ok".utf8))
    }

    @Test func stopRemovesTheSocketFile() throws {
        let path = tempSocketPath()
        let server = SocketServer(path: path, queue: DispatchQueue(label: "test.stop")) { _ in Data("ok\n".utf8) }
        try server.start(mode: 0o600)
        server.stop()
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func aServerReleasedWithoutStopClosesItsSocket() throws {
        let path = tempSocketPath()
        defer { unlink(path) }
        _ = try startEchoServer(at: path, label: "test.released")
        Thread.sleep(forTimeInterval: 0.2)  // the cancel handler closes the socket on the server's queue
        #expect(throws: SocketError.system(call: "connect", code: ECONNREFUSED)) {
            try SocketClient(path: path, timeout: 1)
        }
    }

    @Test func connectingToAMissingSocketFails() {
        #expect(throws: SocketError.self) { try SocketClient(path: "/tmp/fc-missing-\(getpid()).sock", timeout: 3) }
    }

    @Test func aTooLongPathIsRejected() {
        let path = "/tmp/" + String(repeating: "x", count: 120)
        #expect(throws: SocketError.pathTooLong(path)) { try SocketClient(path: path, timeout: 3) }
    }

    /// Only a user who is not root is refused the chown to nobody's group (65534).
    @Test(.enabled(if: getuid() != 0)) func aFailedStartLeavesNoSocketFile() throws {
        let path = tempSocketPath()
        let server = SocketServer(path: path, queue: DispatchQueue(label: "test.failed")) { _ in Data("ok\n".utf8) }
        #expect(throws: SocketError.self) { try server.start(mode: 0o660, groupID: 65534) }
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func aTimedOutExchangeShutsTheConnection() throws {
        let path = tempSocketPath()
        let server = SocketServer(path: path, queue: DispatchQueue(label: "test.slow")) { line in
            Thread.sleep(forTimeInterval: 0.6)
            return Data("echo:".utf8) + line + Data([0x0A])
        }
        try server.start(mode: 0o600)
        defer { server.stop() }
        let client = try SocketClient(path: path, timeout: 0.3)
        #expect(throws: SocketError.timedOut) { try client.exchange(Data("first".utf8)) }
        // The late reply to "first" is due by now; the client must fail instead of passing it off
        // as the reply to "second".
        Thread.sleep(forTimeInterval: 0.5)
        #expect(throws: SocketError.system(call: "write", code: EPIPE)) { try client.exchange(Data("second".utf8)) }
    }

    @Test func twoLinesInOneReadAreAnsweredInOrder() throws {
        let path = tempSocketPath()
        let server = try startEchoServer(at: path, label: "test.two")
        defer { server.stop() }
        let fd = try rawConnection(to: path)
        defer { close(fd) }
        #expect(UnixSocket.writeAll(fd, Data("one\ntwo\n".utf8)))
        #expect(receive(fd, lines: 2) == "echo:one\necho:two\n")
    }

    @Test func anOversizedRequestIsDropped() throws {
        let path = tempSocketPath()
        let server = try startEchoServer(at: path, label: "test.oversized")
        defer { server.stop() }
        let fd = try rawConnection(to: path)
        defer { close(fd) }
        // No newline: the server closes the connection once the unfinished line passes the limit.
        #expect(UnixSocket.writeAll(fd, Data(repeating: 0x61, count: SocketServer.maxRequestBytes + 1)))
        #expect(receive(fd, lines: 1) == "")
        #expect(try SocketClient(path: path, timeout: 3).exchange(Data("next".utf8)) == Data("echo:next".utf8))
    }
}
