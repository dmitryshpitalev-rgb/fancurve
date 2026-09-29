import Darwin

public struct FanLimits: Equatable, Sendable {
    public let min: Double
    public let max: Double

    init(min: Double, max: Double) {
        self.min = min
        self.max = max
    }
}

public enum SystemInfo {
    /// `hw.model`, e.g. "MacBookPro16,1".
    public static func hardwareModel() -> String? {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    /// Stock F?Mn / F?Mx for fans 0..<count as the SMC reports them; nil if any read fails. Whether a
    /// range makes sense is FanCurveCore's rule (`FanRange.isUsable`), which the daemon applies.
    public static func stockFanLimits(smc: SMCAccess, count: Int) -> [FanLimits]? {
        var limits: [FanLimits] = []
        for index in 0..<count {
            guard let minKey = SMCKey("F\(index)Mn"), let maxKey = SMCKey("F\(index)Mx"),
                  let low = try? smc.readValue(minKey), let high = try? smc.readValue(maxKey) else { return nil }
            limits.append(FanLimits(min: low, max: high))
        }
        return limits
    }
}
