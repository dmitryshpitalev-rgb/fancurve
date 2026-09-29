@testable import FanCurveHardware

/// In-memory SMC where every key is a little-endian `flt ` value.
final class FakeSMC: SMCAccess {
    var values: [String: Double]
    /// Successful writes in order, e.g. "F0Md=1".
    var writes: [String] = []
    /// Keys whose writes throw SMC error 0x86 (what the real SMC answers for a rejected write).
    var failingWrites: Set<String> = []
    /// Keys whose writes succeed but do not change the stored value.
    var ignoredWrites: Set<String> = []
    /// `keyInfo` calls, failed ones included.
    var keyInfoLookups = 0

    init(_ values: [String: Double]) {
        self.values = values
    }

    func keyInfo(_ key: SMCKey) throws -> SMCKeyInfo {
        keyInfoLookups += 1
        guard values[key.name] != nil else { throw SMCError.smcResult(0x84) }
        return SMCKeyInfo(size: 4, type: "flt ")
    }

    func readBytes(_ key: SMCKey, info: SMCKeyInfo) throws -> [UInt8] {
        guard let value = values[key.name], let bytes = SMCCodec.encode(type: "flt ", value: value, size: 4) else {
            throw SMCError.smcResult(0x84)
        }
        return bytes
    }

    func readValue(_ key: SMCKey) throws -> Double? {
        guard let value = values[key.name] else { throw SMCError.smcResult(0x84) }
        return value
    }

    func writeValue(_ key: SMCKey, _ value: Double) throws {
        if failingWrites.contains(key.name) { throw SMCError.smcResult(0x86) }
        writes.append("\(key.name)=\(Int(value))")
        if !ignoredWrites.contains(key.name) {
            values[key.name] = value
        }
    }
}
