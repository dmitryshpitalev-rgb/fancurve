import FanCurveCore
import Foundation
import Testing
@testable import FanCurveIPC

@Suite struct DaemonClientTests {
    /// A stand-in daemon: config and history succeed, the GPU policy fails.
    func startStub(at path: String) throws -> SocketServer {
        let server = SocketServer(path: path, queue: DispatchQueue(label: "test.stub")) { line in
            guard let request = try? LineCodec.decode(Request.self, from: line) else { return Data("{}\n".utf8) }
            let reply: Data?
            switch request.cmd {
            case .getConfig:
                reply = try? LineCodec.encode(Response.success(id: request.id, Config.defaults))
            case .history:
                reply = try? LineCodec.encode(Response.success(id: request.id, [Sample]()))
            case .setGPUPolicy:
                reply = try? LineCodec.encode(Response<EmptyData>.failure(id: request.id, "pmset failed"))
            default:
                reply = try? LineCodec.encode(Response<EmptyData>(id: request.id, ok: true, data: nil, error: nil))
            }
            return reply ?? Data("{}\n".utf8)
        }
        try server.start(mode: 0o600)
        return server
    }

    @Test func typedCallsRoundTrip() throws {
        let path = tempSocketPath()
        let server = try startStub(at: path)
        defer { server.stop() }
        let client = try DaemonClient(path: path)
        #expect(try client.getConfig() == .defaults)
        #expect(try client.history(seconds: 5).isEmpty)
    }

    @Test func remoteErrorsAndEmptyRepliesThrow() throws {
        let path = tempSocketPath()
        let server = try startStub(at: path)
        defer { server.stop() }
        let client = try DaemonClient(path: path)
        #expect(throws: DaemonError.remote("pmset failed")) { try client.setGPUPolicy(true) }
        #expect(throws: DaemonError.emptyReply) { try client.retry() }
    }
}
