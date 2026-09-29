/// A four-character SMC key such as "F0Mn" or "FS! ".
public struct SMCKey: Hashable, CustomStringConvertible, Sendable {
    let code: UInt32

    init(code: UInt32) {
        self.code = code
    }

    /// Returns nil unless `name` is exactly four ASCII characters.
    public init?(_ name: String) {
        let bytes = Array(name.utf8)
        guard bytes.count == 4, bytes.allSatisfy({ $0 < 0x80 }) else { return nil }
        var value: UInt32 = 0
        for byte in bytes {
            value = (value << 8) | UInt32(byte)
        }
        code = value
    }

    public var name: String { FourCC.string(code) }
    public var description: String { name }
}

enum FourCC {
    static func string(_ code: UInt32) -> String {
        let bytes: [UInt8] = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
