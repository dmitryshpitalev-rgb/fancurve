/// Detects a daemon that keeps crashing and restarting.
public enum CrashLoopGuard {
    public static let windowSeconds = 60.0
    public static let maxStarts = 5

    /// Adds `now` (Unix seconds) to the recent starts. Returns the list to persist and whether to enter safe mode.
    public static func recordStart(at now: Double, previous: [Double]) -> (starts: [Double], tripped: Bool) {
        let recent = previous.filter { $0 <= now && now - $0 < windowSeconds } + [now]
        return (recent, recent.count >= maxStarts)
    }
}
