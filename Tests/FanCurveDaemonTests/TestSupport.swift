import Foundation

/// A fresh directory under /tmp, short enough for unix socket paths. The caller removes it.
func makeTempDir() throws -> URL {
    let url = URL(fileURLWithPath: "/tmp/fc-\(getpid())-\(UInt32.random(in: 0...UInt32.max))")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func permissions(of url: URL) throws -> Int? {
    try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
}
