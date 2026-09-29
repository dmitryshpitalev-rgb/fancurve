/// Converts between raw SMC bytes and numbers.
/// Integer and fixed-point types are big-endian; `flt ` is little-endian (verified on MacBookPro16,1).
public enum SMCCodec {
    public static func decode(type: String, bytes: [UInt8]) -> Double? {
        switch type {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            let low = UInt32(bytes[0]) | UInt32(bytes[1]) << 8
            let high = UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: low | high))
        case "fpe2":
            guard bytes.count >= 2 else { return nil }
            return Double(bigEndian16(bytes)) / 4
        case "sp78":
            guard bytes.count >= 2 else { return nil }
            return Double(Int16(bitPattern: bigEndian16(bytes))) / 256
        case "ui8 ", "flag":
            guard bytes.count >= 1 else { return nil }
            return Double(bytes[0])
        case "si8 ":
            guard bytes.count >= 1 else { return nil }
            return Double(Int8(bitPattern: bytes[0]))
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Double(bigEndian16(bytes))
        case "si16":
            guard bytes.count >= 2 else { return nil }
            return Double(Int16(bitPattern: bigEndian16(bytes)))
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            return Double(bigEndian32(bytes))
        default:
            return nil
        }
    }

    /// Returns exactly `size` bytes, or nil if the type is unsupported or the value does not fit.
    static func encode(type: String, value: Double, size: Int) -> [UInt8]? {
        guard value.isFinite else { return nil }
        let bytes: [UInt8]
        switch type {
        case "flt ":
            let bits = Float(value).bitPattern
            bytes = [0, 8, 16, 24].map { UInt8(truncatingIfNeeded: bits >> $0) }
        case "fpe2":
            let raw = (value * 4).rounded()
            guard raw >= 0, raw <= Double(UInt16.max) else { return nil }
            let v = UInt16(raw)
            bytes = [UInt8(v >> 8), UInt8(v & 0xFF)]
        case "ui8 ", "flag":
            guard value >= 0, value <= 255, value == value.rounded() else { return nil }
            bytes = [UInt8(value)]
        case "ui16":
            guard value >= 0, value <= Double(UInt16.max), value == value.rounded() else { return nil }
            let v = UInt16(value)
            bytes = [UInt8(v >> 8), UInt8(v & 0xFF)]
        case "ui32":
            guard value >= 0, value <= Double(UInt32.max), value == value.rounded() else { return nil }
            let v = UInt32(value)
            bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: v >> $0) }
        default:
            return nil
        }
        guard bytes.count <= size else { return nil }
        return bytes + [UInt8](repeating: 0, count: size - bytes.count)
    }

    private static func bigEndian16(_ b: [UInt8]) -> UInt16 {
        UInt16(b[0]) << 8 | UInt16(b[1])
    }

    private static func bigEndian32(_ b: [UInt8]) -> UInt32 {
        let high = UInt32(b[0]) << 24 | UInt32(b[1]) << 16
        let low = UInt32(b[2]) << 8 | UInt32(b[3])
        return high | low
    }
}
