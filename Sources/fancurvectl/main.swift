import FanCurveCore
import FanCurveIPC
import Foundation

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func prettyJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}

let invocation: CtlInvocation
do {
    invocation = try Ctl.parse(Array(CommandLine.arguments.dropFirst()))
} catch {
    fail("\(error)\n\n\(Ctl.usage)", code: 2)
}
if invocation.command == .version {
    print("fancurvectl \(FanCurveVersion.string)")
    exit(0)
}

do {
    let client = try DaemonClient(path: invocation.socketPath)
    switch invocation.command {
    case .status(let json):
        let snapshot = try client.status()
        print(try json ? prettyJSON(snapshot) : StatusText.render(snapshot))
    case .history(let seconds):
        print(StatusText.csv(try client.history(seconds: seconds)), terminator: "")
    case .configGet:
        print(try prettyJSON(try client.getConfig()))
    case .configSet(let path):
        let config = try Config.decode(Data(contentsOf: URL(fileURLWithPath: path)))
        print(try prettyJSON(try client.setConfig(config)))
    case .enable:
        print(StatusText.render(try client.setEnabled(true)))
    case .disable:
        print(StatusText.render(try client.setEnabled(false)))
    case .gpu(let on):
        print(StatusText.gpuPolicy(try client.setGPUPolicy(on)))
    case .retry:
        print(StatusText.render(try client.retry()))
    case .version:
        break  // answered above, without the daemon
    }
} catch SocketError.system(call: "connect", let code) where code == ENOENT || code == ECONNREFUSED {
    fail("the daemon is not running (is FanCurve installed?)")
} catch SocketError.system(call: "connect", code: EACCES) {
    fail("only administrators can talk to the daemon")
} catch SocketError.timedOut {
    fail("the daemon did not answer in time")
} catch {
    fail("\(error)")
}
