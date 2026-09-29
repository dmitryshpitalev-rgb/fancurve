import FanCurveCore
@testable import FanCurveDaemon
@testable import FanCurveHardware

final class FakeGPUSwitch: GPUSwitchControl {
    var values: GPUSwitchValues
    var reads = 0
    var sets: [GPUSwitchValues] = []
    var failReads = false
    var failSets = false

    init(_ values: GPUSwitchValues) {
        self.values = values
    }

    func read() throws -> GPUSwitchValues {
        reads += 1
        if failReads { throw GPUSwitchError.unreadable }
        return values
    }

    func set(_ new: GPUSwitchValues) throws {
        sets.append(new)
        if failSets { throw GPUSwitchError.unreadable }
        values = new
    }
}

final class FakeSensors: SensorSource {
    var values: [String: Double]

    init(_ values: [String: Double]) {
        self.values = values
    }

    func read() -> [String: Double] { values }
}

final class FakeActuator: FanActuating {
    var calls: [String] = []
    var failApply = false
    var failRelease = false
    var failTakes = 0
    var verifyResult = true

    func take() throws {
        calls.append("take")
        if failTakes > 0 {
            failTakes -= 1
            throw SMCError.smcResult(0x86)
        }
    }

    func apply(rpm: [Int]) throws {
        calls.append("apply \(rpm)")
        if failApply { throw SMCError.smcResult(0x86) }
    }

    func release() throws {
        calls.append("release")
        if failRelease { throw SMCError.smcResult(0x86) }
    }

    func verify(targetRPM: [Int]) -> Bool {
        calls.append("verify")
        return verifyResult
    }
}

/// An SMC that knows the keys in `keys` and nothing else.
final class KeySetSMC: SMCAccess {
    let keys: Set<String>

    init(_ keys: Set<String>) {
        self.keys = keys
    }

    func keyInfo(_ key: SMCKey) throws -> SMCKeyInfo {
        guard keys.contains(key.name) else { throw SMCError.smcResult(0x84) }
        return SMCKeyInfo(size: 4, type: "flt ")
    }

    func readBytes(_ key: SMCKey, info: SMCKeyInfo) throws -> [UInt8] { throw SMCError.smcResult(0x84) }
    func readValue(_ key: SMCKey) throws -> Double? { throw SMCError.smcResult(0x84) }
    func writeValue(_ key: SMCKey, _ value: Double) throws { throw SMCError.smcResult(0x86) }
}

final class FakeChecks: HardwareChecks {
    var model: String? = "MacBookPro16,1"
    var missing: Set<String> = []
    var ranges: [FanRange]? = [FanRange(minRPM: 1800, maxRPM: 5600), FanRange(minRPM: 1700, maxRPM: 5200)]
    var rangeReads = 0

    func modelIdentifier() -> String? { model }

    func missingKeys(_ names: [String]) -> [String] { names.filter { missing.contains($0) } }

    func stockFanRanges(count: Int) -> [FanRange]? {
        rangeReads += 1
        return ranges
    }
}
