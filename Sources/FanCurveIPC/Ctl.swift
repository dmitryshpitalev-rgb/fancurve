import FanCurveCore

public enum CtlCommand: Equatable {
    case status(json: Bool)
    case history(seconds: Int)
    case configGet
    case configSet(path: String)
    case enable
    case disable
    case gpu(on: Bool)
    case retry
    case version
}

public struct CtlInvocation: Equatable {
    public var socketPath: String
    public var command: CtlCommand

    public init(socketPath: String, command: CtlCommand) {
        self.socketPath = socketPath
        self.command = command
    }
}

public struct CtlError: Error, Equatable, CustomStringConvertible {
    public let message: String
    public var description: String { message }
}

/// `fancurvectl`: the debugging client of the daemon socket. Not the main interface.
public enum Ctl {
    public static let usage = """
        usage: fancurvectl [--socket PATH] <command>
          status [--json]     mode, readings, demand, fans, auto-graphics
          history [SECONDS]   the last SECONDS (1-\(HistoryLimits.seconds), default 60) of samples as CSV
          config get          print the active config
          config set FILE     validate FILE and apply its curves and smoothing
          enable | disable    curve control on / hand the fans back to macOS
          gpu on | off        auto-graphics: the Radeon on the charger / restore the old values
          retry               leave safe mode
          version             print the version
        """

    public static func parse(_ arguments: [String]) throws -> CtlInvocation {
        var arguments = arguments
        var socketPath = DaemonSocket.path
        if arguments.first == "--socket" {
            guard arguments.count >= 2 else { throw CtlError(message: "--socket needs a path") }
            socketPath = arguments[1]
            arguments.removeFirst(2)
        }
        guard let verb = arguments.first else { throw CtlError(message: "no command") }
        let rest = Array(arguments.dropFirst())
        let command: CtlCommand
        switch (verb, rest) {
        case ("status", []): command = .status(json: false)
        case ("status", ["--json"]): command = .status(json: true)
        case ("history", []): command = .history(seconds: 60)
        case ("history", let values) where values.count == 1:
            guard let seconds = Int(values[0]), (1...HistoryLimits.seconds).contains(seconds) else {
                throw CtlError(message: "history: SECONDS must be 1-\(HistoryLimits.seconds)")
            }
            command = .history(seconds: seconds)
        case ("config", ["get"]): command = .configGet
        case ("config", let values) where values.count == 2 && values[0] == "set": command = .configSet(path: values[1])
        case ("enable", []): command = .enable
        case ("disable", []): command = .disable
        case ("gpu", ["on"]): command = .gpu(on: true)
        case ("gpu", ["off"]): command = .gpu(on: false)
        case ("retry", []): command = .retry
        case ("version", []): command = .version
        default: throw CtlError(message: "unknown command: \(arguments.joined(separator: " "))")
        }
        return CtlInvocation(socketPath: socketPath, command: command)
    }
}
