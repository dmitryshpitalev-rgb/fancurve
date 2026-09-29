import FanCurveCore
import Foundation

/// A `pmset gpuswitch` pair: 0 integrated, 1 discrete, 2 automatic.
public struct GPUSwitchValues: Codable, Equatable, Sendable {
    public var ac: Int
    public var battery: Int

    init(ac: Int, battery: Int) {
        self.ac = ac
        self.battery = battery
    }

    /// On the charger always the Radeon, on battery automatic switching.
    static let chargerDiscrete = GPUSwitchValues(ac: 1, battery: 2)
}

/// state.json: stock fan ranges, the gpuswitch values from before auto-graphics, recent starts.
public struct DaemonState: Codable, Equatable, Sendable {
    var fans: [FanRange]?
    public var gpuSwitchOriginal: GPUSwitchValues?
    var starts: [Double]

    init(fans: [FanRange]? = nil, gpuSwitchOriginal: GPUSwitchValues? = nil, starts: [Double] = []) {
        self.fans = fans
        self.gpuSwitchOriginal = gpuSwitchOriginal
        self.starts = starts
    }
}

public struct StateStore {
    let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// A missing file starts empty: the stock ranges are then read from the SMC again. A broken file
    /// starts empty too, with an error: it holds the only record of the gpuswitch values from before
    /// auto-graphics. The file is moved aside to state.json.bad, and the error says so only if the
    /// move worked.
    public func load() -> (state: DaemonState, error: String?) {
        guard FileManager.default.fileExists(atPath: url.path) else { return (DaemonState(), nil) }
        do {
            return (try JSONDecoder().decode(DaemonState.self, from: Data(contentsOf: url)), nil)
        } catch {
            let kept = AtomicFile.keepAsBad(url) ? ", the file was kept as state.json.bad" : ""
            return (DaemonState(), "state.json could not be read (\(error.localizedDescription)); an empty state is in use\(kept)")
        }
    }

    func save(_ state: DaemonState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try AtomicFile.write(try encoder.encode(state), to: url, permissions: 0o600)
    }
}
