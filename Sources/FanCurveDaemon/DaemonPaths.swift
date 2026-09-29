import FanCurveCore
import Foundation

/// Where the daemon keeps its files. Tests and `--dry-run` root them in a scratch directory.
public struct DaemonPaths: Equatable, Sendable {
    public var supportDir: URL
    public var runDir: URL
    public var socket: URL

    init(supportDir: URL, runDir: URL, socket: URL) {
        self.supportDir = supportDir
        self.runDir = runDir
        self.socket = socket
    }

    public var config: URL { supportDir.appendingPathComponent("config.json") }
    public var state: URL { supportDir.appendingPathComponent("state.json") }
    public var heartbeat: URL { runDir.appendingPathComponent("heartbeat") }

    public static let system = DaemonPaths(
        supportDir: URL(fileURLWithPath: "/Library/Application Support/FanCurve"),
        runDir: URL(fileURLWithPath: "/var/run/fancurve"),
        socket: URL(fileURLWithPath: DaemonSocket.path)
    )

    /// Everything under `base`. Keep `base` short: a unix socket path must fit in 104 bytes.
    public static func rooted(at base: URL) -> DaemonPaths {
        DaemonPaths(supportDir: base.appendingPathComponent("support"),
                    runDir: base.appendingPathComponent("run"),
                    socket: base.appendingPathComponent("fancurve.sock"))
    }

    /// Creates the support and run directories (0755) if they are missing. /var/run is emptied at boot.
    public func prepare() throws {
        for directory in [supportDir, runDir] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o755])
        }
    }
}
