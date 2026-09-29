import FanCurveCore
import FanCurveIPC
import Foundation

/// Fixed, plausible data for `FanCurve --snapshot` and the tests: no daemon, no clock.
public enum PreviewData {
    /// A fixed "now" (a September afternoon) keeps the snapshots stable.
    public static let now: Double = 1_790_000_000

    static let ranges = HardwareProfile.macBookPro16_1.fans

    /// The status's readings as the curves see them, which its tiles show: the preview hour ends on
    /// them, so the readout above the charts agrees with the tiles.
    static let readings = (cpu: 76.5, gpu: 60.8, chassis: 38.3, power: 45.9)

    /// A CPU under a two-thread load, the Radeon awake, the curve leading at 48%.
    public static let snapshot: Snapshot = {
        let raw = PerChannel<Double?>(cpu: 78, gpu: 61, chassis: 38.4, power: 47.2)
        let filtered = PerChannel<Double?>(cpu: readings.cpu, gpu: readings.gpu, chassis: readings.chassis,
                                           power: readings.power)
        let demand = Demand.evaluate(curves: Config.defaults.curves, values: filtered)
        let fans = ranges.map { range in
            FanState(actualRPM: Double(range.rpm(forPercent: demand.percent)), targetRPM: range.rpm(forPercent: demand.percent),
                     minRPM: range.minRPM, maxRPM: range.maxRPM)
        }
        return Snapshot(t: now, mode: .active, raw: raw, filtered: filtered, demand: demand,
                        outputPercent: demand.percent, fans: fans,
                        gpuPolicy: GPUPolicyState(enabled: false, acSwitch: 2, batterySwitch: 2),
                        configError: nil, smcError: nil)
    }()

    /// An hour at 1 Hz ending at `endingAt`: idle with a slow drift, the Radeon asleep from minute 20
    /// to 35, a 90 s two-thread load from minute 50 and its cool-down (shaped after docs/acceptance.md),
    /// then the status's load for the last two minutes, ending on its readings.
    public static func history(endingAt end: Double = now, seconds: Int = 3600) -> [Sample] {
        (0..<seconds).map { index in
            let t = end - Double(seconds - 1 - index)
            let minute = (t - (now - 3599)) / 60
            let load = minute >= 50 && minute < 51.5 ? 1.0 : 0.0
            let after = minute >= 51.5 ? exp(-(minute - 51.5) * 1.2) : 0
            let wiggle = sin(t / 23) * 1.5 + sin(t / 7) * 0.6
            var cpu = 57 + wiggle + load * 26 + after * 20
            var gpu: Double? = minute >= 20 && minute < 35 ? nil : 56 + wiggle / 2 + load * 6
            var chassis = 36 + minute * 0.03 + (load + after) * 1.5
            var power = 12 + abs(wiggle) * 2 + load * 35 + after * 5
            // The status's load: the dies heat up within 20 s, the chassis over the two minutes, and
            // the jitter fades out on the status itself.
            let left = now - t
            if left < 120 {
                func toward(_ value: Double, _ target: Double, _ weight: Double) -> Double {
                    value * (1 - weight) + target * weight  // exactly `target` at weight 1
                }
                let heat = min((120 - left) / 20, 1)
                let jitter = sin(left / 9) * 0.8 + sin(left / 4) * 0.3
                cpu = toward(cpu, readings.cpu + jitter, heat)
                gpu = gpu.map { toward($0, readings.gpu + jitter / 2, heat) }
                power = toward(power, readings.power + jitter * 2, heat)
                chassis = toward(chassis, readings.chassis, min((120 - left) / 120, 1))
            }
            let values = PerChannel<Double?>(cpu: cpu, gpu: gpu, chassis: chassis, power: power)
            let demand = Demand.evaluate(curves: Config.defaults.curves, values: values)
            let fans = ranges.map { Double($0.rpm(forPercent: demand.percent)) as Double? }
            return Sample(t: t, cpu: cpu, gpu: gpu, chassis: chassis, power: power, demandPercent: demand.percent,
                          leading: demand.leading, fanRPM: fans, mode: .active)
        }
    }
}

/// A daemon that answers every call at once from fixed data: `--snapshot` and tests.
public final class PreviewLink: DaemonLinking {
    public var snapshot: Snapshot
    public var samples: [Sample]
    public var config: Config

    public init(snapshot: Snapshot = PreviewData.snapshot, samples: [Sample] = PreviewData.history(), config: Config = .defaults) {
        self.snapshot = snapshot
        self.samples = samples
        self.config = config
    }

    public func status(_ done: @escaping (Result<Snapshot, Error>) -> Void) {
        done(.success(snapshot))
    }

    public func history(seconds: Int, _ done: @escaping (Result<[Sample], Error>) -> Void) {
        let start = (samples.last?.t ?? 0) - Double(seconds)
        done(.success(samples.filter { $0.t > start }))
    }

    public func getConfig(_ done: @escaping (Result<Config, Error>) -> Void) {
        done(.success(config))
    }

    public func setConfig(_ config: Config, _ done: @escaping (Result<Config, Error>) -> Void) {
        // Like the daemon: only the curves and the smoothing are taken.
        self.config.curves = config.curves
        self.config.smoothing = config.smoothing
        done(.success(self.config))
    }

    public func setEnabled(_ enabled: Bool, _ done: @escaping (Result<Snapshot, Error>) -> Void) {
        snapshot.mode = enabled ? .active : .disabled
        done(.success(snapshot))
    }

    public func setGPUPolicy(_ enabled: Bool, _ done: @escaping (Result<GPUPolicyState, Error>) -> Void) {
        snapshot.gpuPolicy = GPUPolicyState(enabled: enabled, acSwitch: enabled ? 1 : 2, batterySwitch: 2)
        done(.success(snapshot.gpuPolicy))
    }

    public func retry(_ done: @escaping (Result<Snapshot, Error>) -> Void) {
        snapshot.mode = .active
        done(.success(snapshot))
    }
}

/// A daemon that is not there: the red state of the popup.
public final class UnreachableLink: DaemonLinking {
    public init() {}

    private func fail<T>(_ done: (Result<T, Error>) -> Void) {
        done(.failure(SocketError.system(call: "connect", code: ENOENT)))
    }

    public func status(_ done: @escaping (Result<Snapshot, Error>) -> Void) { fail(done) }
    public func history(seconds: Int, _ done: @escaping (Result<[Sample], Error>) -> Void) { fail(done) }
    public func getConfig(_ done: @escaping (Result<Config, Error>) -> Void) { fail(done) }
    public func setConfig(_ config: Config, _ done: @escaping (Result<Config, Error>) -> Void) { fail(done) }
    public func setEnabled(_ enabled: Bool, _ done: @escaping (Result<Snapshot, Error>) -> Void) { fail(done) }
    public func setGPUPolicy(_ enabled: Bool, _ done: @escaping (Result<GPUPolicyState, Error>) -> Void) { fail(done) }
    public func retry(_ done: @escaping (Result<Snapshot, Error>) -> Void) { fail(done) }
}
