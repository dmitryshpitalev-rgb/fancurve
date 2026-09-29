/// When the watchdog hands the fans back to macOS.
public enum WatchdogPolicy {
    public static let staleSeconds = 5.0
    public static let wakeGraceSeconds = 15.0

    /// `heartbeatAge` is nil when the heartbeat file does not exist: no daemon has ticked since boot.
    /// Right after a wake the heartbeat is legitimately old, so the check is skipped for a while.
    public static func shouldRelease(heartbeatAge: Double?, secondsSinceWake: Double?) -> Bool {
        if let sinceWake = secondsSinceWake, sinceWake < wakeGraceSeconds {
            return false
        }
        guard let age = heartbeatAge else { return true }
        return age > staleSeconds
    }

    /// Dispatch timers run on uptime, which stops during sleep: when the wall clock advanced more
    /// than the uptime did between two watchdog ticks, the machine slept in between.
    public static let sleepDetectionSeconds = 2.0

    public static func sleptBetween(wallSeconds: Double, uptimeSeconds: Double) -> Bool {
        wallSeconds - uptimeSeconds > sleepDetectionSeconds
    }
}
