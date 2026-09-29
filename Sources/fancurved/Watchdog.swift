import FanCurveCore
import FanCurveDaemon
import FanCurveHardware
import Foundation

/// Hands the fans back to macOS when the daemon's heartbeat goes stale; that hand-back is the only
/// SMC write it makes.
func runWatchdog() -> Never {
    requireRoot()
    let profile = HardwareProfile.macBookPro16_1
    let heartbeat = DaemonPaths.system.heartbeat
    let log: (String) -> Void = { watchdogLogger.log("\($0, privacy: .public)") }
    let actuator: ForcedActuator
    do {
        actuator = try openActuator(profile).actuator
    } catch {
        log("\(error); exiting for launchd to retry")
        exit(1)
    }

    let queue = DispatchQueue(label: "local.fancurve.watchdog")
    var lastWake: Date?
    // Each logged at most once per stale episode; both reset the moment the heartbeat is healthy
    // again, so a later success (or failure) in the next episode is reported once more.
    var loggedRelease = false
    var loggedFailure = false
    let power = PowerEvents(willSleep: {}, didWake: { lastWake = Date() })
    if !power.start(queue: queue) { log("sleep notifications unavailable") }

    let timer = DispatchSource.makeTimerSource(queue: queue)
    // `didWake` above can race the first post-wake tick: dispatch timers run on uptime, which
    // freezes during sleep, so that first tick can fire before kIOMessageSystemHasPoweredOn does.
    // Each tick therefore also compares how far the wall clock and uptime moved since the previous
    // tick — a wall clock that jumped ahead of uptime means the machine slept in between.
    var previousTickWall = Date()
    var previousTickUptime = ProcessInfo.processInfo.systemUptime
    timer.schedule(deadline: .now() + 1, repeating: .seconds(1), leeway: .milliseconds(100))
    timer.setEventHandler {
        let now = Date()
        let currentUptime = ProcessInfo.processInfo.systemUptime
        if WatchdogPolicy.sleptBetween(wallSeconds: now.timeIntervalSince(previousTickWall),
                                        uptimeSeconds: currentUptime - previousTickUptime) {
            lastWake = now
        }
        previousTickWall = now
        previousTickUptime = currentUptime
        let age = Heartbeat.age(heartbeat, now: now)
        let sinceWake = lastWake.map { now.timeIntervalSince($0) }
        guard WatchdogPolicy.shouldRelease(heartbeatAge: age, secondsSinceWake: sinceWake) else {
            loggedRelease = false
            loggedFailure = false
            return
        }
        let ageText = age.map { String(format: "%.1f s", $0) } ?? "no file"
        do {
            try actuator.release()
            if !loggedRelease {
                log("heartbeat stale (\(ageText)), fans handed back to macOS")
                loggedRelease = true
            }
        } catch {
            if !loggedFailure {
                log("heartbeat stale (\(ageText)), handing the fans back failed: \(error)")
                loggedFailure = true
            }
        }
    }
    timer.resume()
    log("started")
    withExtendedLifetime((timer, power)) {
        dispatchMain()
    }
}
