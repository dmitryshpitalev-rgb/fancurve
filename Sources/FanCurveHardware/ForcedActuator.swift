enum ActuatorError: Error, Equatable, CustomStringConvertible {
    case invalidKey(String)
    case keyCountMismatch(modes: Int, targets: Int)
    case fanCountMismatch(expected: Int, got: Int)

    var description: String {
        switch self {
        case .invalidKey(let name): return "not a 4-character SMC key: '\(name)'"
        case .keyCountMismatch(let modes, let targets): return "\(modes) mode keys but \(targets) target keys"
        case .fanCountMismatch(let expected, let got): return "expected \(expected) fan targets, got \(got)"
        }
    }
}

/// Forced fan mode: `take` sets F?Md=1, `apply` writes F?Tg, `release` sets F?Md=0 and macOS
/// takes over again. The SMC clears F?Md across sleep, so the daemon checks with `verify` and
/// re-asserts. Writes need root.
public final class ForcedActuator {
    private let smc: SMCAccess
    private let modeKeys: [SMCKey]
    private let targetKeys: [SMCKey]
    /// Key info for `verify`, which runs on every quiet tick: looked up on first use and kept once
    /// found. Not at init, so a transient lookup failure cannot cost the startup release.
    private var infos: [SMCKey: SMCKeyInfo] = [:]

    public init(smc: SMCAccess, modeKeys: [String], targetKeys: [String]) throws {
        guard modeKeys.count == targetKeys.count else {
            throw ActuatorError.keyCountMismatch(modes: modeKeys.count, targets: targetKeys.count)
        }
        func key(_ name: String) throws -> SMCKey {
            guard let key = SMCKey(name) else { throw ActuatorError.invalidKey(name) }
            return key
        }
        self.smc = smc
        self.modeKeys = try modeKeys.map(key)
        self.targetKeys = try targetKeys.map(key)
    }

    public func take() throws {
        for key in modeKeys {
            try smc.writeValue(key, 1)
        }
    }

    public func apply(rpm: [Int]) throws {
        guard rpm.count == targetKeys.count else {
            throw ActuatorError.fanCountMismatch(expected: targetKeys.count, got: rpm.count)
        }
        for (key, value) in zip(targetKeys, rpm) {
            try smc.writeValue(key, Double(value))
        }
    }

    /// Hands every fan back to macOS. Keeps going past a failed fan; throws the first error at the end.
    public func release() throws {
        var firstError: Error?
        for key in modeKeys {
            do {
                try smc.writeValue(key, 0)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
    }

    /// True when every fan reads back forced mode and its target to within 1 rpm.
    public func verify(targetRPM: [Int]) -> Bool {
        guard targetRPM.count == targetKeys.count else { return false }
        for index in modeKeys.indices {
            guard let mode = try? read(modeKeys[index]), mode == 1,
                  let target = try? read(targetKeys[index]),
                  abs(target - Double(targetRPM[index])) < 1 else { return false }
        }
        return true
    }

    private func read(_ key: SMCKey) throws -> Double? {
        let info: SMCKeyInfo
        if let known = infos[key] {
            info = known
        } else {
            info = try smc.keyInfo(key)
            infos[key] = info
        }
        return SMCCodec.decode(type: info.type, bytes: try smc.readBytes(key, info: info))
    }
}
