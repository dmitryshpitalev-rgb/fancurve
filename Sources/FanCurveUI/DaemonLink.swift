import FanCurveCore
import FanCurveIPC
import Foundation

/// Asynchronous calls to the daemon. The socket link answers on its callback queue (the main queue in
/// the app); the preview and test links answer right away.
public protocol DaemonLinking: AnyObject {
    func status(_ done: @escaping (Result<Snapshot, Error>) -> Void)
    func history(seconds: Int, _ done: @escaping (Result<[Sample], Error>) -> Void)
    func getConfig(_ done: @escaping (Result<Config, Error>) -> Void)
    func setConfig(_ config: Config, _ done: @escaping (Result<Config, Error>) -> Void)
    func setEnabled(_ enabled: Bool, _ done: @escaping (Result<Snapshot, Error>) -> Void)
    func setGPUPolicy(_ enabled: Bool, _ done: @escaping (Result<GPUPolicyState, Error>) -> Void)
    func retry(_ done: @escaping (Result<Snapshot, Error>) -> Void)
}

/// The socket link: one `DaemonClient`, used from one serial queue (the client is not thread-safe
/// and blocks). A broken connection is dropped, so the next call reconnects — the daemon may have
/// restarted; a refusal from the daemon itself keeps the connection.
public final class DaemonLink: DaemonLinking {
    private let path: String
    private let timeout: Double
    private let callbackQueue: DispatchQueue
    private let queue = DispatchQueue(label: "local.fancurve.app.link")
    private var client: DaemonClient?

    /// `timeout` is 2 s, not the client's 3 s: a button must not hang the popup, and the daemon
    /// answers in milliseconds.
    public init(path: String = DaemonSocket.path, timeout: Double = 2, callbackQueue: DispatchQueue = .main) {
        self.path = path
        self.timeout = timeout
        self.callbackQueue = callbackQueue
    }

    public func status(_ done: @escaping (Result<Snapshot, Error>) -> Void) {
        perform({ try $0.status() }, done)
    }

    public func history(seconds: Int, _ done: @escaping (Result<[Sample], Error>) -> Void) {
        perform({ try $0.history(seconds: seconds) }, done)
    }

    public func getConfig(_ done: @escaping (Result<Config, Error>) -> Void) {
        perform({ try $0.getConfig() }, done)
    }

    public func setConfig(_ config: Config, _ done: @escaping (Result<Config, Error>) -> Void) {
        perform({ try $0.setConfig(config) }, done)
    }

    public func setEnabled(_ enabled: Bool, _ done: @escaping (Result<Snapshot, Error>) -> Void) {
        perform({ try $0.setEnabled(enabled) }, done)
    }

    public func setGPUPolicy(_ enabled: Bool, _ done: @escaping (Result<GPUPolicyState, Error>) -> Void) {
        perform({ try $0.setGPUPolicy(enabled) }, done)
    }

    public func retry(_ done: @escaping (Result<Snapshot, Error>) -> Void) {
        perform({ try $0.retry() }, done)
    }

    private func perform<T>(_ call: @escaping (DaemonClient) throws -> T, _ done: @escaping (Result<T, Error>) -> Void) {
        queue.async {
            let result: Result<T, Error>
            do {
                let client = try self.client ?? DaemonClient(path: self.path, timeout: self.timeout)
                self.client = client
                result = .success(try call(client))
            } catch {
                if !(error is DaemonError) {
                    self.client = nil
                }
                result = .failure(error)
            }
            self.callbackQueue.async { done(result) }
        }
    }
}
