import FanCurveCore
import FanCurveIPC
import Foundation
import Testing
@testable import FanCurveUI

struct TimedOut: Error {}

/// Starts a call and waits up to 5 s for its result.
func waitFor<T>(_ start: (@escaping (Result<T, Error>) -> Void) -> Void) throws -> T {
    let done = DispatchSemaphore(value: 0)
    var result: Result<T, Error>?
    start { value in
        result = value
        done.signal()
    }
    guard done.wait(timeout: .now() + 5) == .success, let result else { throw TimedOut() }
    return try result.get()
}

@Suite struct DaemonLinkTests {
    /// A stand-in daemon: status answers, setEnabled is refused.
    func startStub(at path: String) throws -> SocketServer {
        let server = SocketServer(path: path, queue: DispatchQueue(label: "test.ui.stub")) { line in
            guard let request = try? LineCodec.decode(Request.self, from: line) else { return Data("{}\n".utf8) }
            let reply: Data?
            switch request.cmd {
            case .status:
                reply = try? LineCodec.encode(Response.success(id: request.id, PreviewData.snapshot))
            case .setEnabled:
                reply = try? LineCodec.encode(Response<EmptyData>.failure(id: request.id, "safe mode"))
            default:
                reply = try? LineCodec.encode(Response<EmptyData>.failure(id: request.id, "unsupported"))
            }
            return reply ?? Data("{}\n".utf8)
        }
        try server.start(mode: 0o600)
        return server
    }

    @Test func callsArriveOnTheCallbackQueue() throws {
        let path = tempSocketPath()
        let server = try startStub(at: path)
        defer { server.stop() }
        let callbacks = DispatchQueue(label: "test.ui.callbacks")
        let key = DispatchSpecificKey<Bool>()
        callbacks.setSpecific(key: key, value: true)
        let link = DaemonLink(path: path, timeout: 1, callbackQueue: callbacks)
        let (snapshot, onCallbacks) = try waitFor { done in
            link.status { result in done(result.map { ($0, DispatchQueue.getSpecific(key: key) == true) }) }
        }
        #expect(snapshot == PreviewData.snapshot)
        #expect(onCallbacks)
    }

    @Test func aRefusalIsTheDaemonsMessage() throws {
        let path = tempSocketPath()
        let server = try startStub(at: path)
        defer { server.stop() }
        let link = DaemonLink(path: path, timeout: 1, callbackQueue: DispatchQueue(label: "test.ui.callbacks"))
        #expect(throws: DaemonError.remote("safe mode")) { try waitFor { link.setEnabled(false, $0) } }
        #expect(try waitFor { link.status($0) }.mode == .active)  // the connection survived the refusal
    }

    @Test func itReconnectsAfterTheDaemonRestarts() throws {
        let path = tempSocketPath()
        var server = try startStub(at: path)
        let link = DaemonLink(path: path, timeout: 1, callbackQueue: DispatchQueue(label: "test.ui.callbacks"))
        #expect(try waitFor { link.status($0) }.mode == .active)
        server.stop()
        #expect(throws: (any Error).self) { try waitFor { link.status($0) } }
        server = try startStub(at: path)
        defer { server.stop() }
        #expect(try waitFor { link.status($0) }.mode == .active)
    }

    @Test func noDaemonIsAnError() {
        let link = DaemonLink(path: tempSocketPath(), timeout: 1, callbackQueue: DispatchQueue(label: "test.ui.callbacks"))
        #expect(throws: (any Error).self) { try waitFor { link.status($0) } }
    }

    @Test func itRecoversAfterAReadTimeout() throws {
        let path = tempSocketPath()
        var calls = 0
        let server = SocketServer(path: path, queue: DispatchQueue(label: "test.ui.slow")) { line in
            calls += 1
            if calls == 1 { Thread.sleep(forTimeInterval: 1.5) }  // longer than the link's 1 s timeout
            // Each answer says which call it answers, so a late answer read as the next one shows.
            var snapshot = PreviewData.snapshot
            snapshot.t = Double(calls)
            guard let request = try? LineCodec.decode(Request.self, from: line),
                  let reply = try? LineCodec.encode(Response.success(id: request.id, snapshot)) else {
                return Data("{}\n".utf8)
            }
            return reply
        }
        try server.start(mode: 0o600)
        defer { server.stop() }
        let link = DaemonLink(path: path, timeout: 1, callbackQueue: DispatchQueue(label: "test.ui.callbacks"))
        do {
            _ = try waitFor { link.status($0) }
            Issue.record("a 1.5 s answer arrived inside a 1 s timeout")
        } catch {
            #expect(UIText.Table(.ru).connectionProblem(error) == "демон не ответил вовремя")
        }
        // The stub answers on one serial queue, which is still asleep: let it finish first, so the
        // next call has its whole 1 s.
        Thread.sleep(forTimeInterval: 0.6)
        #expect(try waitFor { link.status($0) }.t == 2)
    }
}
