import Foundation

// MARK: Mode JSON

extension Mode: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "starting": self = .starting
        case "active": self = .active
        case "disabled": self = .disabled
        case "released": self = .released(try container.decode(ReleaseReason.self, forKey: .reason))
        case "safe": self = .safe(try container.decode(SafeReason.self, forKey: .reason))
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "unknown mode '\(kind)'")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .starting:
            try container.encode("starting", forKey: .kind)
        case .active:
            try container.encode("active", forKey: .kind)
        case .disabled:
            try container.encode("disabled", forKey: .kind)
        case .released(let reason):
            try container.encode("released", forKey: .kind)
            try container.encode(reason, forKey: .reason)
        case .safe(let reason):
            try container.encode("safe", forKey: .kind)
            try container.encode(reason, forKey: .reason)
        }
    }
}

// MARK: Payloads

public struct FanState: Codable, Equatable, Sendable {
    public var actualRPM: Double?
    public var targetRPM: Int?
    public var minRPM: Double
    public var maxRPM: Double

    public init(actualRPM: Double?, targetRPM: Int?, minRPM: Double, maxRPM: Double) {
        self.actualRPM = actualRPM
        self.targetRPM = targetRPM
        self.minRPM = minRPM
        self.maxRPM = maxRPM
    }

    /// The range the daemon drives this fan in.
    public var range: FanRange { FanRange(minRPM: minRPM, maxRPM: maxRPM) }
}

public struct GPUPolicyState: Codable, Equatable, Sendable {
    public var enabled: Bool
    /// `pmset` gpuswitch values as currently set: 0 integrated, 1 discrete, 2 automatic.
    public var acSwitch: Int?
    public var batterySwitch: Int?

    public init(enabled: Bool, acSwitch: Int?, batterySwitch: Int?) {
        self.enabled = enabled
        self.acSwitch = acSwitch
        self.batterySwitch = batterySwitch
    }
}

/// One history point, recorded once per second.
public struct Sample: Codable, Equatable, Sendable {
    public var t: Double
    public var cpu: Double?
    public var gpu: Double?
    public var chassis: Double?
    public var power: Double?
    public var demandPercent: Double
    public var leading: CurveKind?
    public var fanRPM: [Double?]
    public var mode: Mode

    public init(t: Double, cpu: Double?, gpu: Double?, chassis: Double?, power: Double?,
                demandPercent: Double, leading: CurveKind?, fanRPM: [Double?], mode: Mode) {
        self.t = t
        self.cpu = cpu
        self.gpu = gpu
        self.chassis = chassis
        self.power = power
        self.demandPercent = demandPercent
        self.leading = leading
        self.fanRPM = fanRPM
        self.mode = mode
    }
}

public struct Snapshot: Codable, Equatable, Sendable {
    public var t: Double
    public var mode: Mode
    public var raw: PerChannel<Double?>
    public var filtered: PerChannel<Double?>
    public var demand: DemandResult
    public var outputPercent: Double?
    public var fans: [FanState]
    public var gpuPolicy: GPUPolicyState
    public var configError: String?
    /// The last failed SMC write, kept for 10 s after it (Engine.smcErrorHoldSeconds); nil otherwise.
    public var smcError: String?

    public init(t: Double, mode: Mode, raw: PerChannel<Double?>, filtered: PerChannel<Double?>, demand: DemandResult,
                outputPercent: Double?, fans: [FanState], gpuPolicy: GPUPolicyState,
                configError: String?, smcError: String?) {
        self.t = t
        self.mode = mode
        self.raw = raw
        self.filtered = filtered
        self.demand = demand
        self.outputPercent = outputPercent
        self.fans = fans
        self.gpuPolicy = gpuPolicy
        self.configError = configError
        self.smcError = smcError
    }
}

// MARK: Requests and responses

/// Where the installed daemon listens; the dry run and `fancurvectl --socket` use other paths.
public enum DaemonSocket {
    public static let path = "/var/run/fancurve.sock"
}

public enum Command: String, Codable, Sendable {
    case status, history, getConfig, setConfig, setEnabled, setGPUPolicy, retry
}

public struct RequestArgs: Codable, Equatable, Sendable {
    public var seconds: Int?
    public var config: Config?
    public var enabled: Bool?

    public init(seconds: Int? = nil, config: Config? = nil, enabled: Bool? = nil) {
        self.seconds = seconds
        self.config = config
        self.enabled = enabled
    }
}

public struct Request: Codable, Equatable, Sendable {
    public var id: Int
    public var cmd: Command
    public var args: RequestArgs?

    public init(id: Int, cmd: Command, args: RequestArgs? = nil) {
        self.id = id
        self.cmd = cmd
        self.args = args
    }
}

public struct EmptyData: Codable, Equatable, Sendable {
    public init() {}
}

public struct Response<T: Codable & Sendable>: Codable, Sendable {
    public var id: Int
    public var ok: Bool
    public var data: T?
    public var error: String?

    public init(id: Int, ok: Bool, data: T?, error: String?) {
        self.id = id
        self.ok = ok
        self.data = data
        self.error = error
    }

    public static func success(id: Int, _ data: T) -> Response {
        Response(id: id, ok: true, data: data, error: nil)
    }

    public static func failure(id: Int, _ message: String) -> Response {
        Response(id: id, ok: false, data: nil, error: message)
    }
}

extension Response: Equatable where T: Equatable {}

/// Newline-delimited JSON: one message per line.
public enum LineCodec {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        var data = try JSONEncoder().encode(value)
        data.append(0x0A)
        return data
    }

    public static func decode<T: Decodable>(_ type: T.Type, from line: Data) throws -> T {
        var line = line
        if line.last == 0x0A {
            line.removeLast()
        }
        return try JSONDecoder().decode(type, from: line)
    }
}
