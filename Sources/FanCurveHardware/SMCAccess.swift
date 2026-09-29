/// What the fan layer needs from the SMC. `SMCClient` is the real one; tests use an in-memory fake.
public protocol SMCAccess: AnyObject {
    func keyInfo(_ key: SMCKey) throws -> SMCKeyInfo
    func readBytes(_ key: SMCKey, info: SMCKeyInfo) throws -> [UInt8]
    func readValue(_ key: SMCKey) throws -> Double?
    func writeValue(_ key: SMCKey, _ value: Double) throws
}

extension SMCClient: SMCAccess {}
