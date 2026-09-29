import FanCurveCore
import FanCurveDaemon
import FanCurveHardware
import FanCurveIPC
import Foundation

/// The tick loop, the socket and the power notifications all start in every mode, safe mode
/// included, so the menubar can see why. Everything that touches the engine runs on `queue`; the
/// socket has its own queue and hops onto the engine's for each request.
func runDaemon(dryRunRoot: String?) -> Never {
    let dryRun = dryRunRoot != nil
    if !dryRun { requireRoot() }
    let paths = dryRunRoot.map { DaemonPaths.rooted(at: URL(fileURLWithPath: $0)) } ?? .system
    let log: (String) -> Void = { message in
        (dryRun ? dryRunLogger : logger).log("\(message, privacy: .public)")
        if dryRun { FileHandle.standardError.write(Data((message + "\n").utf8)) }
    }
    do {
        try paths.prepare()
    } catch {
        fail("cannot create \(paths.supportDir.path) and \(paths.runDir.path): \(error)")
    }

    let profile = HardwareProfile.macBookPro16_1
    let opened: (smc: SMCClient, actuator: ForcedActuator)?
    do {
        opened = try openActuator(profile)
    } catch {
        opened = nil
        log("\(error)")
    }
    let smc = opened?.smc
    let sensors: SensorSource
    if let smc {
        let live = LiveSensors(smc: smc, names: profile.columnNames)
        if !live.unavailable.isEmpty { log("sensors not found, not read: \(live.unavailable.joined(separator: ", "))") }
        sensors = live
    } else {
        sensors = NoSensors()
    }
    let actuator: FanActuating
    if dryRun {
        actuator = LoggingActuator(log: log)
    } else if let forced = opened?.actuator {
        actuator = forced
    } else {
        actuator = UnavailableActuator()
    }
    let gpuSwitch: GPUSwitchControl = dryRun ? DryRunGPUSwitch(log: log) : PMSetSwitch()
    let engine = Engine(profile: profile, paths: paths, sensors: sensors, actuator: actuator,
                        checks: SMCHardwareChecks(smc: smc), gpuPolicy: GPUPolicy(control: gpuSwitch), log: log)

    let queue = DispatchQueue(label: "local.fancurve.engine", autoreleaseFrequency: .workItem)

    // Signal handlers go in before `start`, on `queue`: a signal during setup waits for the step in
    // progress, then hands the fans back. `shutdown` is safe before `start`: it only looks at the mode.
    var signalSources: [DispatchSourceSignal] = []
    for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
        signal(signalNumber, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: queue)
        source.setEventHandler {
            engine.shutdown(now: uptime())
            exit(0)
        }
        source.resume()
        signalSources.append(source)
    }

    queue.sync { engine.start(now: uptime(), wall: wallClock()) }

    let handler = CommandHandler(engine: engine, clock: { (now: uptime(), wall: wallClock()) })
    let server = SocketServer(path: paths.socket.path, queue: DispatchQueue(label: "local.fancurve.socket")) { line in
        queue.sync { handler.handle(line) }
    }
    do {
        try server.start(mode: 0o660, groupID: dryRun ? nil : getgrnam("admin")?.pointee.gr_gid)
    } catch {
        log("socket \(paths.socket.path) not started: \(error)")
    }

    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now(), repeating: Engine.tickSeconds, leeway: .milliseconds(50))
    timer.setEventHandler { engine.tick(now: uptime(), wall: wallClock()) }
    timer.resume()

    let power = PowerEvents(willSleep: { engine.willSleep(now: uptime()) },
                            didWake: { engine.didWake(now: uptime()) })
    if !power.start(queue: queue) { log("sleep notifications unavailable") }

    log("fancurved \(FanCurveVersion.string) " + (dryRun ? "started (dry run, files in \(paths.supportDir.deletingLastPathComponent().path))" : "started"))
    withExtendedLifetime((timer, power, server, signalSources)) {
        dispatchMain()
    }
}
