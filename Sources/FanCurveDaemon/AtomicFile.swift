import Foundation

struct FileError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

enum AtomicFile {
    /// Writes a temporary file next to `url`, sets `permissions`, then renames it over `url`, so a
    /// reader (or a crash mid-write) never sees half a file.
    static func write(_ data: Data, to url: URL, permissions: Int) throws {
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(getpid()).tmp")
        do {
            try data.write(to: temporary)
            try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: temporary.path)
            guard rename(temporary.path, url.path) == 0 else {
                throw FileError(message: "rename to \(url.path) failed: \(String(cString: strerror(errno)))")
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    /// Moves a file that could not be read aside to `<name>.bad`, over an older one; true if it moved.
    static func keepAsBad(_ url: URL) -> Bool {
        let bad = url.appendingPathExtension("bad")
        try? FileManager.default.removeItem(at: bad)
        return (try? FileManager.default.moveItem(at: url, to: bad)) != nil
    }
}
