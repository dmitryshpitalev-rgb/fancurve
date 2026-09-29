import FanCurveCore
import Foundation

/// A status as the daemon would report it: the demand is computed from `filtered` with `config`,
/// and the output follows the demand. Defaults: a warm CPU under load, the Radeon awake.
func makeSnapshot(mode: Mode = .active,
                  raw: PerChannel<Double?> = PerChannel(cpu: 78, gpu: 61, chassis: 38.4, power: 47.2),
                  filtered: PerChannel<Double?> = PerChannel(cpu: 76.5, gpu: 60.8, chassis: 38.3, power: 45.9),
                  config: Config = .defaults,
                  fans: [FanState] = [FanState(actualRPM: 3650, targetRPM: 3650, minRPM: 1836, maxRPM: 5616),
                                      FanState(actualRPM: 3380, targetRPM: 3380, minRPM: 1700, maxRPM: 5200)]) -> Snapshot {
    let demand = Demand.evaluate(curves: config.curves, values: filtered)
    return Snapshot(t: 1_790_000_000, mode: mode, raw: raw, filtered: filtered, demand: demand,
                    outputPercent: demand.percent, fans: fans,
                    gpuPolicy: GPUPolicyState(enabled: false, acSwitch: 2, batterySwitch: 2),
                    configError: nil, smcError: nil)
}

/// A socket path under /tmp, short enough for sockaddr_un.
func tempSocketPath() -> String {
    "/tmp/fc-ui-\(getpid())-\(UInt32.random(in: 0...UInt32.max)).sock"
}
