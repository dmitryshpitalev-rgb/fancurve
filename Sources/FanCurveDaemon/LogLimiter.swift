/// The same log message at most once a minute, each message on its own clock.
struct LogLimiter {
    static let intervalSeconds = 60.0
    private var lastLogged: [String: Double] = [:]

    mutating func shouldLog(_ message: String, now: Double) -> Bool {
        if let at = lastLogged[message], now >= at, now - at < Self.intervalSeconds { return false }
        lastLogged[message] = now
        return true
    }
}
