import FanCurveCore
import Foundation

/// config.json: written only by the daemon, after validation, atomically.
public struct ConfigStore {
    let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// A missing file is a first run: defaults, no error. A broken file means the defaults and an
    /// error, shown in the Snapshot; the file is moved aside to config.json.bad, and the error says
    /// so only if the move worked.
    public func load() -> (config: Config, error: String?) {
        guard FileManager.default.fileExists(atPath: url.path) else { return (Config.defaults, nil) }
        do {
            return (try Config.decode(Data(contentsOf: url)), nil)
        } catch {
            let kept = AtomicFile.keepAsBad(url) ? ", the file was kept as config.json.bad" : ""
            return (Config.defaults, "config.json could not be read (\(error)); the defaults are in use\(kept)")
        }
    }

    func save(_ config: Config) throws {
        try config.validate()
        try AtomicFile.write(try config.encoded(), to: url, permissions: 0o644)
    }
}
