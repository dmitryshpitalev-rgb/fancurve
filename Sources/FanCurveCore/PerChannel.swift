/// The four measured inputs. Curves are a separate notion (`CurveKind`): the hotspot curve reads
/// the hotter of `cpu` and `gpu`.
public enum ChannelID: String, Codable, CaseIterable, Sendable {
    case cpu, gpu, chassis, power
}

/// One value per channel. Encodes as a JSON object with keys cpu, gpu, chassis, power. nil values
/// are written as null; decoding needs every key.
public struct PerChannel<Value> {
    public var cpu: Value
    public var gpu: Value
    public var chassis: Value
    public var power: Value

    public init(cpu: Value, gpu: Value, chassis: Value, power: Value) {
        self.cpu = cpu
        self.gpu = gpu
        self.chassis = chassis
        self.power = power
    }

    public subscript(id: ChannelID) -> Value {
        get {
            switch id {
            case .cpu: return cpu
            case .gpu: return gpu
            case .chassis: return chassis
            case .power: return power
            }
        }
        set {
            switch id {
            case .cpu: cpu = newValue
            case .gpu: gpu = newValue
            case .chassis: chassis = newValue
            case .power: power = newValue
            }
        }
    }

    public func map<T>(_ transform: (Value) throws -> T) rethrows -> PerChannel<T> {
        PerChannel<T>(cpu: try transform(cpu), gpu: try transform(gpu), chassis: try transform(chassis), power: try transform(power))
    }
}

extension PerChannel: Equatable where Value: Equatable {}
extension PerChannel: Sendable where Value: Sendable {}
extension PerChannel: Codable where Value: Codable {}

extension PerChannel where Value == Double? {
    public static var empty: PerChannel<Double?> {
        PerChannel(cpu: nil, gpu: nil, chassis: nil, power: nil)
    }
}
