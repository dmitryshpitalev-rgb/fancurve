import FanCurveCore
import FanCurveHardware
import Foundation
import os

let logger = Logger(subsystem: "local.fancurve", category: "daemon")
let watchdogLogger = Logger(subsystem: "local.fancurve", category: "watchdog")
/// `--dry-run` logs here instead of `local.fancurve`, so a live daemon's log is never mixed with a
/// developer's dry-run session.
let dryRunLogger = Logger(subsystem: "local.fancurve.dry-run", category: "daemon")

let usage = """
    usage: fancurved                           the daemon (root, started by launchd)
           fancurved --watchdog                hand the fans back when the daemon's heartbeat goes stale (root)
           fancurved --restore                 hand the fans back and restore gpuswitch (root, for uninstall)
           fancurved --dry-run --root DIR      the daemon without root: no SMC or pmset writes, files in DIR
           fancurved --simulate <trace.csv> --profile <hardware-profile.json> [--config <config.json>]
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

func requireRoot() {
    guard getuid() == 0 else { fail("fancurved must run as root; to try it without root: fancurved --dry-run --root DIR") }
}

/// Monotonic seconds for the controller.
func uptime() -> Double {
    ProcessInfo.processInfo.systemUptime
}

/// Unix time for history, heartbeat and crash-loop starts.
func wallClock() -> Double {
    Date().timeIntervalSince1970
}

/// Why `openActuator` failed, and at which of its two steps.
struct ActuatorSetupError: Error, CustomStringConvertible {
    let description: String
}

/// AppleSMC and the forced-mode actuator on the profile's fan keys, for the daemon, the watchdog
/// and `--restore`.
func openActuator(_ profile: HardwareProfile) throws -> (smc: SMCClient, actuator: ForcedActuator) {
    let smc: SMCClient
    do {
        smc = try SMCClient()
    } catch {
        throw ActuatorSetupError(description: "AppleSMC could not be opened: \(error)")
    }
    do {
        return (smc, try ForcedActuator(smc: smc, modeKeys: profile.fanMode, targetKeys: profile.fanTarget))
    } catch {
        throw ActuatorSetupError(description: "the fan keys could not be set up: \(error)")
    }
}
