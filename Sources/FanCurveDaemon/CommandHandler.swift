import FanCurveCore
import Foundation

/// One JSON request line in, one JSON response line (ending in a newline) out.
/// Called on the engine's queue.
public final class CommandHandler {
    public typealias Clock = () -> (now: Double, wall: Double)

    private let engine: Engine
    private let clock: Clock

    public init(engine: Engine, clock: @escaping Clock) {
        self.engine = engine
        self.clock = clock
    }

    public func handle(_ line: Data) -> Data {
        let request: Request
        do {
            request = try LineCodec.decode(Request.self, from: line)
        } catch {
            return failure(0, "bad request: \(error)")
        }
        let (now, wall) = clock()
        let id = request.id
        let args = request.args
        switch request.cmd {
        case .status:
            return success(id, engine.snapshot(now: now, wall: wall))
        case .history:
            guard let seconds = args?.seconds, (1...HistoryLimits.seconds).contains(seconds) else {
                return failure(id, "history: seconds must be 1 to \(HistoryLimits.seconds)")
            }
            return success(id, engine.history(seconds: seconds))
        case .getConfig:
            return success(id, engine.config)
        case .setConfig:
            guard let config = args?.config else { return failure(id, "setConfig: no config argument") }
            do {
                return success(id, try engine.setConfig(config))
            } catch {
                return failure(id, explain(error, "could not apply the config"))
            }
        case .setEnabled:
            guard let enabled = args?.enabled else { return failure(id, "setEnabled: no enabled argument") }
            do {
                try engine.setEnabled(enabled, now: now)
                return success(id, engine.snapshot(now: now, wall: wall))
            } catch {
                return failure(id, explain(error, "could not save the setting"))
            }
        case .setGPUPolicy:
            guard let enabled = args?.enabled else { return failure(id, "setGPUPolicy: no enabled argument") }
            do {
                return success(id, try engine.setGPUPolicy(enabled, now: now))
            } catch {
                return failure(id, explain(error, "could not switch graphics"))
            }
        case .retry:
            engine.retry(now: now)
            return success(id, engine.snapshot(now: now, wall: wall))
        }
    }

    private func success<T: Codable & Sendable>(_ id: Int, _ data: T) -> Data {
        encode(Response.success(id: id, data))
    }

    private func failure(_ id: Int, _ message: String) -> Data {
        encode(Response<EmptyData>.failure(id: id, message))
    }

    private func encode<T: Encodable>(_ value: T) -> Data {
        (try? LineCodec.encode(value)) ?? Data("{\"id\":0,\"ok\":false,\"error\":\"could not encode the reply\"}\n".utf8)
    }

    /// A ValidationError says what is wrong in words; any other error is a system failure, reported
    /// with a lead and its technical detail after the colon. English, like everything the daemon
    /// says: the app translates what it can and shows the rest as it is.
    private func explain(_ error: Error, _ context: String) -> String {
        if let validation = error as? ValidationError { return validation.message }
        return "\(context): \(error)"
    }
}
