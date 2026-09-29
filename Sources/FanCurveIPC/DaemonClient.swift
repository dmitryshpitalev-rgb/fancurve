import FanCurveCore
import Foundation

public enum DaemonError: Error, Equatable, CustomStringConvertible {
    case remote(String)
    case emptyReply

    public var description: String {
        switch self {
        case .remote(let message): return message
        case .emptyReply: return "the daemon answered ok without data"
        }
    }
}

/// Typed requests over the daemon socket. One connection, reused; not thread-safe. The request id is
/// informational: the connection carries one request at a time and shuts on any failed exchange, so
/// the reply read is always the one to the request just sent.
public final class DaemonClient {
    private let socket: SocketClient
    private var nextID = 1

    public init(path: String = DaemonSocket.path, timeout: Double = 3) throws {
        socket = try SocketClient(path: path, timeout: timeout)
    }

    public func status() throws -> Snapshot { try call(.status, nil, Snapshot.self) }
    public func history(seconds: Int) throws -> [Sample] { try call(.history, RequestArgs(seconds: seconds), [Sample].self) }
    public func getConfig() throws -> Config { try call(.getConfig, nil, Config.self) }
    public func setConfig(_ config: Config) throws -> Config { try call(.setConfig, RequestArgs(config: config), Config.self) }
    public func setEnabled(_ enabled: Bool) throws -> Snapshot { try call(.setEnabled, RequestArgs(enabled: enabled), Snapshot.self) }
    public func setGPUPolicy(_ enabled: Bool) throws -> GPUPolicyState {
        try call(.setGPUPolicy, RequestArgs(enabled: enabled), GPUPolicyState.self)
    }
    public func retry() throws -> Snapshot { try call(.retry, nil, Snapshot.self) }

    private func call<T: Codable & Sendable>(_ cmd: Command, _ args: RequestArgs?, _ type: T.Type) throws -> T {
        let id = nextID
        nextID += 1
        let reply = try socket.exchange(try LineCodec.encode(Request(id: id, cmd: cmd, args: args)))
        let response = try LineCodec.decode(Response<T>.self, from: reply)
        guard response.ok else { throw DaemonError.remote(response.error ?? "unknown error") }
        guard let data = response.data else { throw DaemonError.emptyReply }
        return data
    }
}
