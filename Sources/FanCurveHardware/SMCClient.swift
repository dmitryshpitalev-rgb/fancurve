import Foundation
import IOKit

struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

/// Mirrors the kernel's SMCKeyData_t (80 bytes). `padding` stands in for the C tail padding of
/// SMCKeyInfoData, which Swift does not count in its size, so that `result` lands at offset 40.
struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
         0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

public struct SMCKeyInfo: Equatable, Sendable {
    public let size: Int
    public let type: String

    init(size: Int, type: String) {
        self.size = size
        self.type = type
    }
}

public enum SMCError: Error, CustomStringConvertible {
    case serviceNotFound
    case openFailed(kern_return_t)
    case callFailed(kern_return_t)
    case smcResult(UInt8)
    case cannotEncode(type: String)
    case wrongSize(expected: Int, got: Int)
    case tooLong(Int)

    /// kIOReturnNotPrivileged is a C macro Swift cannot import.
    static let notPrivileged = kern_return_t(bitPattern: 0xE000_02C1)

    public var description: String {
        switch self {
        case .serviceNotFound:
            return "AppleSMC service not found"
        case .openFailed(let code):
            return "IOServiceOpen failed: \(Self.hex(code))"
        case .callFailed(let code):
            return code == Self.notPrivileged ? "not privileged: run with sudo" : "SMC call failed: \(Self.hex(code))"
        case .smcResult(let code):
            return code == 0x84 ? "key not found" : "SMC error 0x\(String(code, radix: 16))"
        case .cannotEncode(let type):
            return "cannot encode value for SMC type '\(type)' (unsupported type or out of range)"
        case .wrongSize(let expected, let got):
            return "key takes \(expected) bytes, got \(got)"
        case .tooLong(let count):
            return "an SMC call carries at most \(SMCClient.maxDataBytes) bytes, got \(count)"
        }
    }

    private static func hex(_ code: kern_return_t) -> String {
        "0x" + String(UInt32(bitPattern: code), radix: 16)
    }
}

/// Synchronous client for the AppleSMC user client. Reads work without root; writes need root.
public final class SMCClient {
    /// The size of `SMCParamStruct.bytes`: the most one call reads or writes.
    static let maxDataBytes = 32

    private var connection: io_connect_t = 0

    private static let handleYPCEvent: UInt32 = 2

    private enum Command: UInt8 {
        case readBytes = 5
        case writeBytes = 6
        case readIndex = 8
        case readKeyInfo = 9
    }

    public init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.serviceNotFound }
        defer { IOObjectRelease(service) }
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == kIOReturnSuccess else { throw SMCError.openFailed(result) }
    }

    deinit {
        IOServiceClose(connection)
    }

    public func keyInfo(_ key: SMCKey) throws -> SMCKeyInfo {
        var input = SMCParamStruct()
        input.key = key.code
        input.data8 = Command.readKeyInfo.rawValue
        let output = try call(input)
        return SMCKeyInfo(size: Int(output.keyInfo.dataSize), type: FourCC.string(output.keyInfo.dataType))
    }

    public func readBytes(_ key: SMCKey, info: SMCKeyInfo) throws -> [UInt8] {
        var input = SMCParamStruct()
        input.key = key.code
        input.keyInfo.dataSize = UInt32(info.size)
        input.data8 = Command.readBytes.rawValue
        let output = try call(input)
        let all = withUnsafeBytes(of: output.bytes) { Array($0) }
        return Array(all.prefix(info.size))
    }

    public func readValue(_ key: SMCKey) throws -> Double? {
        let info = try keyInfo(key)
        return SMCCodec.decode(type: info.type, bytes: try readBytes(key, info: info))
    }

    public func writeBytes(_ key: SMCKey, _ bytes: [UInt8]) throws {
        try write(key, bytes, info: try keyInfo(key))
    }

    public func writeValue(_ key: SMCKey, _ value: Double) throws {
        let info = try keyInfo(key)
        guard let bytes = SMCCodec.encode(type: info.type, value: value, size: info.size) else {
            throw SMCError.cannotEncode(type: info.type)
        }
        try write(key, bytes, info: info)
    }

    /// A write fits in one call and fills the key exactly.
    static func checkWriteSize(_ count: Int, keySize: Int) throws {
        guard count <= maxDataBytes else { throw SMCError.tooLong(count) }
        guard count == keySize else { throw SMCError.wrongSize(expected: keySize, got: count) }
    }

    public func keyCount() throws -> Int {
        Int(try readValue(SMCKey("#KEY")!) ?? 0)
    }

    public func key(at index: Int) throws -> SMCKey {
        var input = SMCParamStruct()
        input.data8 = Command.readIndex.rawValue
        input.data32 = UInt32(index)
        return SMCKey(code: try call(input).key)
    }

    /// Both public writes end here, with the key info they already hold: one keyInfo call per write.
    private func write(_ key: SMCKey, _ bytes: [UInt8], info: SMCKeyInfo) throws {
        try Self.checkWriteSize(bytes.count, keySize: info.size)
        var input = SMCParamStruct()
        input.key = key.code
        input.keyInfo.dataSize = UInt32(info.size)
        input.data8 = Command.writeBytes.rawValue
        withUnsafeMutableBytes(of: &input.bytes) { buffer in
            for (index, byte) in bytes.enumerated() {
                buffer[index] = byte
            }
        }
        _ = try call(input)
    }

    private func call(_ input: SMCParamStruct) throws -> SMCParamStruct {
        var input = input
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let result = IOConnectCallStructMethod(
            connection, Self.handleYPCEvent,
            &input, MemoryLayout<SMCParamStruct>.stride,
            &output, &outputSize
        )
        guard result == kIOReturnSuccess else { throw SMCError.callFailed(result) }
        guard output.result == 0 else { throw SMCError.smcResult(output.result) }
        return output
    }
}
