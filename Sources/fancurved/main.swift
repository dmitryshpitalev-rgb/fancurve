import FanCurveDaemon
import Foundation

switch DaemonInvocation.parse(Array(CommandLine.arguments.dropFirst())) {
case .daemon?:
    runDaemon(dryRunRoot: nil)
case .watchdog?:
    runWatchdog()
case .restore?:
    runRestore()
case .dryRun(let root)?:
    runDaemon(dryRunRoot: root)
case .simulate(let trace, let profile, let config)?:
    runSimulation(tracePath: trace, profilePath: profile, configPath: config)
case nil:
    fail(usage)
}
