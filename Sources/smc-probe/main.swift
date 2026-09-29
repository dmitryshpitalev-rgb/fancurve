import FanCurveHardware
import Foundation
import IOKit.ps

let usage = """
usage:
  smc-probe dump [--prefix T,P,F]
  smc-probe read KEY...
  smc-probe value KEY
  smc-probe write KEY VALUE          (sudo)
  smc-probe write-hex KEY HEX        (sudo)
  smc-probe gpu
  smc-probe watch KEY... [--interval S] [--count N]
  smc-probe record --out FILE [--prefix T,P,F | --keys K1,K2,...] [--interval S] [--duration S] [--extras]
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func smcKey(_ name: String) -> SMCKey {
    guard let key = SMCKey(name) else { fail("invalid key '\(name)': need exactly 4 ASCII characters") }
    return key
}

func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
}

func format(_ value: Double?) -> String {
    guard let value else { return "" }
    return String(format: "%.3f", value)
}

/// The options each command takes; any other `--name` is an error rather than silently ignored.
let commandOptions: [String: Set<String>] = [
    "dump": ["prefix"],
    "read": [],
    "value": [],
    "write": [],
    "write-hex": [],
    "gpu": [],
    "watch": ["interval", "count"],
    "record": ["out", "prefix", "keys", "interval", "duration", "extras"],
]

/// Splits arguments into positionals and `--name value` options; `allowed` names the options.
func parseArguments(_ args: ArraySlice<String>, allowed: Set<String>) -> (positional: [String], options: [String: String]) {
    let booleanFlags = Set(["extras"])
    var positional: [String] = []
    var options: [String: String] = [:]
    var iterator = args.makeIterator()
    while let arg = iterator.next() {
        if arg.hasPrefix("--") {
            let name = String(arg.dropFirst(2))
            guard allowed.contains(name) else { fail("unknown option \(arg)\n\(usage)") }
            if booleanFlags.contains(name) {
                options[name] = "1"
            } else {
                guard let value = iterator.next() else { fail("missing value for \(arg)") }
                options[name] = value
            }
        } else {
            positional.append(arg)
        }
    }
    return (positional, options)
}

func positiveNumber(_ options: [String: String], _ name: String) -> Double? {
    guard let raw = options[name] else { return nil }
    guard let value = Double(raw), value > 0 else { fail("--\(name) must be a positive number") }
    return value
}

func positiveInteger(_ options: [String: String], _ name: String) -> Int? {
    guard let raw = options[name] else { return nil }
    guard let value = Int(raw), value > 0 else { fail("--\(name) must be a positive whole number") }
    return value
}

func prefixes(_ options: [String: String]) -> [String] {
    (options["prefix"] ?? "").split(separator: ",").map(String.init)
}

func matches(_ key: SMCKey, _ prefixes: [String]) -> Bool {
    prefixes.isEmpty || prefixes.contains { key.name.hasPrefix($0) }
}

func parseKeys(_ keyNames: [String], _ smc: SMCClient) throws -> [(key: SMCKey, info: SMCKeyInfo)] {
    var result: [(key: SMCKey, info: SMCKeyInfo)] = []
    for name in keyNames {
        guard let key = SMCKey(name) else {
            fail("invalid key '\(name)': need exactly 4 ASCII characters")
        }
        guard let info = try? smc.keyInfo(key) else {
            fail("key '\(name)' does not exist or is not readable")
        }
        result.append((key, info))
    }
    return result
}

/// 0 nominal, 1 fair, 2 serious, 3 critical (ProcessInfo.ThermalState.rawValue). pmset's
/// CPU_Speed_Limit is not recorded: on this Mac it never drops below 98, even with the CPU at 100 °C.
func readThermalState() -> String {
    String(ProcessInfo.processInfo.thermalState.rawValue)
}

/// 1 on AC power, 0 otherwise; empty if IOKit reports no power source.
func readOnAC() -> String {
    guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return "" }
    guard let providing = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() else { return "" }
    return (providing as String) == "AC Power" ? "1" : "0"
}

func describe(_ smc: SMCClient, _ key: SMCKey) throws -> String {
    let info = try smc.keyInfo(key)
    let bytes = try smc.readBytes(key, info: info)
    let value = format(SMCCodec.decode(type: info.type, bytes: bytes))
    return "\(key.name)\t\(info.type)\t\(info.size)\t\(hex(bytes))\t\(value)"
}

/// Keys matching `prefixes` whose current bytes decode to a number.
func numericKeys(_ smc: SMCClient, prefixes: [String]) throws -> [(key: SMCKey, info: SMCKeyInfo)] {
    var result: [(key: SMCKey, info: SMCKeyInfo)] = []
    for index in 0..<(try smc.keyCount()) {
        let key = try smc.key(at: index)
        guard matches(key, prefixes),
              let info = try? smc.keyInfo(key),
              let bytes = try? smc.readBytes(key, info: info),
              SMCCodec.decode(type: info.type, bytes: bytes) != nil else { continue }
        result.append((key, info))
    }
    return result
}

let arguments = CommandLine.arguments
guard arguments.count >= 2, let allowedOptions = commandOptions[arguments[1]] else { fail(usage) }
let command = arguments[1]
let (positional, options) = parseArguments(arguments.dropFirst(2), allowed: allowedOptions)

do {
    let smc = try SMCClient()
    switch command {
    case "dump":
        let wanted = prefixes(options)
        print("key\ttype\tsize\thex\tvalue")
        for index in 0..<(try smc.keyCount()) {
            let key = try smc.key(at: index)
            guard matches(key, wanted), let line = try? describe(smc, key) else { continue }
            print(line)
        }

    case "read":
        guard !positional.isEmpty else { fail(usage) }
        for name in positional {
            guard let key = SMCKey(name) else {
                print("\(name)\terror: invalid key: need exactly 4 ASCII characters")
                continue
            }
            do {
                print(try describe(smc, key))
            } catch {
                print("\(name)\terror: \(error)")
            }
        }

    case "value":
        guard positional.count == 1 else { fail(usage) }
        guard let value = try smc.readValue(smcKey(positional[0])) else {
            fail("\(positional[0]): value is not numeric")
        }
        print(format(value))

    case "write":
        guard positional.count == 2, let value = Double(positional[1]) else { fail(usage) }
        let key = smcKey(positional[0])
        try smc.writeValue(key, value)
        print("\(key.name) <- \(format(value)); read back \(format(try smc.readValue(key)))")

    case "write-hex":
        guard positional.count == 2, positional[1].count % 2 == 0 else { fail(usage) }
        let digits = Array(positional[1])
        let bytes: [UInt8] = stride(from: 0, to: digits.count, by: 2).map { offset in
            guard let byte = UInt8(String(digits[offset...offset + 1]), radix: 16) else {
                fail("invalid hex '\(positional[1])'")
            }
            return byte
        }
        let key = smcKey(positional[0])
        try smc.writeBytes(key, bytes)
        print("\(key.name) <- \(hex(bytes)); read back \(hex(try smc.readBytes(key, info: try smc.keyInfo(key))))")

    case "gpu":
        let stats = GPUStatsReader.read()
        print("temperature\t\(format(stats.temperature))")
        print("power\t\(format(stats.power))")
        print("activity\t\(format(stats.activity))")

    case "watch":
        guard !positional.isEmpty else { fail(usage) }
        let keys = positional.map(smcKey)
        let interval = positiveNumber(options, "interval") ?? 1
        let count = positiveInteger(options, "count")
        let clock = DateFormatter()
        clock.dateFormat = "HH:mm:ss"
        print((["time"] + positional).joined(separator: "\t"))
        var printed = 0
        while count.map({ printed < $0 }) ?? true {
            let values: [String] = keys.map { key in
                guard let value = try? smc.readValue(key) else { return "-" }
                return format(value)
            }
            print(([clock.string(from: Date())] + values).joined(separator: "\t"))
            fflush(stdout)
            printed += 1
            Thread.sleep(forTimeInterval: interval)
        }

    case "record":
        guard let path = options["out"] else { fail(usage) }
        let interval = positiveNumber(options, "interval") ?? 0.5
        let duration = positiveNumber(options, "duration")
        let useExtras = options["extras"] != nil

        let requestedKeys: [(key: SMCKey, info: SMCKeyInfo)]
        if let keyNames = options["keys"] {
            if options["prefix"] != nil {
                fail("--keys and --prefix are mutually exclusive")
            }
            requestedKeys = try parseKeys(keyNames.split(separator: ",").map(String.init), smc)
        } else {
            requestedKeys = try numericKeys(smc, prefixes: prefixes(options))
        }
        // A comma in a key's name would misalign every column of the CSV. No key on this Mac has
        // one; this is a guard, not an expected case.
        let keys = requestedKeys.filter { entry in
            guard entry.key.name.contains(",") else { return true }
            FileHandle.standardError.write(Data("skipping key with a comma in its name: \(entry.key.name)\n".utf8))
            return false
        }

        var header = ["t"] + keys.map { $0.key.name }
            + [LiveSensors.gpuTemperatureColumn, LiveSensors.gpuPowerColumn, "ioreg.gpu.activity"]
        if useExtras {
            header += ["sys.wall", "sys.thermal", "sys.on_ac"]
        }

        guard FileManager.default.createFile(atPath: path, contents: Data((header.joined(separator: ",") + "\n").utf8)),
              let file = FileHandle(forWritingAtPath: path) else { fail("cannot create \(path)") }
        try file.seekToEnd()
        FileHandle.standardError.write(Data("recording \(keys.count) keys to \(path), Ctrl-C to stop\n".utf8))
        let start = Date()
        while duration.map({ Date().timeIntervalSince(start) < $0 }) ?? true {
            try autoreleasepool {
                let t = Date().timeIntervalSince(start)
                var fields = [String(format: "%.3f", t)]
                for entry in keys {
                    let bytes = try? smc.readBytes(entry.key, info: entry.info)
                    fields.append(format(bytes.flatMap { SMCCodec.decode(type: entry.info.type, bytes: $0) }))
                }
                let gpu = GPUStatsReader.read()
                fields += [format(gpu.temperature), format(gpu.power), format(gpu.activity)]
                if useExtras {
                    let wallSeconds = String(format: "%.3f", Date().timeIntervalSince1970)
                    fields += [wallSeconds, readThermalState(), readOnAC()]
                }
                try file.write(contentsOf: Data((fields.joined(separator: ",") + "\n").utf8))
                let elapsed = Date().timeIntervalSince(start) - t
                Thread.sleep(forTimeInterval: max(0, interval - elapsed))
            }
        }
        try file.close()

    default:
        fail(usage)
    }
} catch {
    fail("error: \(error)")
}
