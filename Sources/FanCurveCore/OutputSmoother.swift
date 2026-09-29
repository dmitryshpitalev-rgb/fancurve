/// Rate-limits the fan output: fast up, hold after the last rise, slow down.
struct OutputSmoother: Equatable, Sendable {
    private(set) var output: Double
    private var lastTime: Double?
    private var lastRiseTime: Double?

    init(output: Double = 0) {
        self.output = output
    }

    /// `bypass` jumps straight to `demand` (safety override) and restarts the hold.
    @discardableResult
    mutating func step(demand: Double, at time: Double, smoothing: Smoothing, bypass: Bool = false) -> Double {
        // Time only moves forward, as in ChannelFilter: a stale timestamp must not rewind
        // `lastTime`, or the next real tick computes an inflated dt from it.
        if let last = lastTime, time < last { return output }
        let target = min(max(demand, 0), 100)
        let dt = lastTime.map { time - $0 } ?? 0
        lastTime = time
        if bypass {
            output = target
            lastRiseTime = time
        } else if target >= output {
            lastRiseTime = time
            output = min(target, output + smoothing.upPercentPerSecond * dt)
        } else {
            let holding = lastRiseTime.map { time - $0 < smoothing.holdSeconds } ?? false
            if !holding {
                output = max(target, output - smoothing.downPercentPerSecond * dt)
            }
        }
        return output
    }

    /// Continues from `output` (the fans' current speed when control is taken); the hold starts at `time`.
    mutating func reset(output: Double, at time: Double) {
        self.output = min(max(output, 0), 100)
        lastTime = time
        lastRiseTime = time
    }
}

enum WriteGate {
    /// Whether a new output is worth writing to the SMC.
    static func shouldWrite(_ output: Double, lastWritten: Double?, deadband: Double) -> Bool {
        guard let last = lastWritten else { return true }
        if output == last { return false }
        if output == 0 || output == 100 { return true }
        return abs(output - last) >= deadband
    }
}
