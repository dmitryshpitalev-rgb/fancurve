import Foundation

/// Exponential moving average that tolerates short gaps.
/// A missing sample keeps the last value; `lossTicks` consecutive misses clear it (channel lost).
struct ChannelFilter: Equatable, Sendable {
    let tau: Double
    let lossTicks: Int
    private(set) var value: Double?
    /// True once `lossTicks` samples in a row were missing — the channel is lost,
    /// as opposed to simply not having a value yet.
    var isLost: Bool { missed >= lossTicks }
    private var lastTime: Double?
    private var missed = 0

    init(tau: Double, lossTicks: Int) {
        self.tau = tau
        self.lossTicks = lossTicks
    }

    @discardableResult
    mutating func update(_ sample: Double?, at time: Double) -> Double? {
        guard let sample, sample.isFinite else {
            missed += 1
            if missed >= lossTicks {
                value = nil
                lastTime = nil
            }
            return value
        }
        missed = 0
        if let current = value, let last = lastTime {
            if time > last {
                let alpha = 1 - exp(-(time - last) / tau)
                value = current + alpha * (sample - current)
                lastTime = time
            }
        } else {
            value = sample
            lastTime = time
        }
        return value
    }

    /// Drops the held value but keeps the miss count: a channel that goes dark neither
    /// resurrects a stale reading when it returns nor earns a fresh loss grace.
    mutating func clearValue() {
        value = nil
        lastTime = nil
    }

    mutating func reset() {
        value = nil
        lastTime = nil
        missed = 0
    }
}
