import Foundation

/// The daemon touches this file on every tick in every mode, except while a hand-back is owed
/// (`Engine.releaseOwed`); the watchdog reads its mtime.
public enum Heartbeat {
    static func touch(_ url: URL) -> Bool {
        if utimes(url.path, nil) == 0 { return true }
        let descriptor = open(url.path, O_WRONLY | O_CREAT, 0o644)
        guard descriptor >= 0 else { return false }
        close(descriptor)
        return true
    }

    /// Seconds since the last touch by the wall clock; nil if the file does not exist.
    public static func age(_ url: URL, now: Date = Date()) -> Double? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date else { return nil }
        return now.timeIntervalSince(modified)
    }
}
