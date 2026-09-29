/// One reading of every named value per call: 4-character SMC keys, plus the Radeon's ioreg
/// statistics under `gpuTemperatureColumn` / `gpuPowerColumn` (the names `smc-probe record` uses).
/// Key info is resolved once at init, so a tick costs one SMC call per key. Reads need no root.
public final class LiveSensors {
    public static let gpuTemperatureColumn = "ioreg.gpu.temp"
    public static let gpuPowerColumn = "ioreg.gpu.power"

    private struct Entry {
        let name: String
        let key: SMCKey
        let info: SMCKeyInfo
    }

    private let smc: SMCAccess
    private let entries: [Entry]
    private let readsGPU: Bool
    private let gpuStats: () -> GPUStats
    /// Names skipped at init: not a 4-character key, or the key does not exist on this Mac.
    public let unavailable: [String]

    public init(smc: SMCAccess, names: [String], gpuStats: @escaping () -> GPUStats = GPUStatsReader.read) {
        var entries: [Entry] = []
        var unavailable: [String] = []
        var readsGPU = false
        for name in names {
            if name == Self.gpuTemperatureColumn || name == Self.gpuPowerColumn {
                readsGPU = true
                continue
            }
            // Key info is looked up once, here: a key the SMC does not answer for at start stays out
            // for the life of the process (the daemon logs `unavailable`), and a restart re-reads it.
            guard let key = SMCKey(name), let info = try? smc.keyInfo(key) else {
                unavailable.append(name)
                continue
            }
            entries.append(Entry(name: name, key: key, info: info))
        }
        self.smc = smc
        self.entries = entries
        self.unavailable = unavailable
        self.readsGPU = readsGPU
        self.gpuStats = gpuStats
    }

    /// Values that could not be read are absent from the result.
    public func read() -> [String: Double] {
        var values: [String: Double] = [:]
        for entry in entries {
            if let bytes = try? smc.readBytes(entry.key, info: entry.info),
               let value = SMCCodec.decode(type: entry.info.type, bytes: bytes) {
                values[entry.name] = value
            }
        }
        if readsGPU {
            let stats = gpuStats()
            values[Self.gpuTemperatureColumn] = stats.temperature
            values[Self.gpuPowerColumn] = stats.power
        }
        return values
    }
}
