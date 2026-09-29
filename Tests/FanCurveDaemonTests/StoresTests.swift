import FanCurveCore
import Foundation
import Testing
@testable import FanCurveDaemon

@Suite struct DaemonPathsTests {
    @Test func systemPathsAreTheInstalledOnes() {
        let paths = DaemonPaths.system
        #expect(paths.config.path == "/Library/Application Support/FanCurve/config.json")
        #expect(paths.state.path == "/Library/Application Support/FanCurve/state.json")
        #expect(paths.heartbeat.path == "/var/run/fancurve/heartbeat")
        #expect(paths.socket.path == "/var/run/fancurve.sock")
    }

    @Test func prepareCreatesBothDirectories() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let paths = DaemonPaths.rooted(at: dir)
        try paths.prepare()
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: paths.supportDir.path, isDirectory: &isDirectory) && isDirectory.boolValue)
        #expect(FileManager.default.fileExists(atPath: paths.runDir.path, isDirectory: &isDirectory) && isDirectory.boolValue)
    }
}

@Suite struct ConfigStoreTests {
    @Test func aMissingFileMeansDefaultsWithoutAnError() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let loaded = ConfigStore(url: dir.appendingPathComponent("config.json")).load()
        #expect(loaded.config == .defaults)
        #expect(loaded.error == nil)
    }

    @Test func savesAtomicallyReadableByEveryone() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ConfigStore(url: dir.appendingPathComponent("config.json"))
        var config = Config.defaults
        config.enabled = false
        try store.save(config)
        #expect(store.load().config == config)
        #expect(try permissions(of: store.url) == 0o644)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["config.json"])
    }

    @Test func aBrokenFileIsMovedAsideAndReported() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ConfigStore(url: dir.appendingPathComponent("config.json"))
        try Data("{broken".utf8).write(to: store.url)
        let loaded = store.load()
        #expect(loaded.config == .defaults)
        #expect(loaded.error?.contains("config.json.bad") == true)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("config.json.bad").path))
        #expect(!FileManager.default.fileExists(atPath: store.url.path))
    }

    @Test(.enabled(if: getuid() != 0))  // root ignores the permission bits this test relies on
    func aBrokenFileThatCannotBeMovedIsNotSaidToBeKept() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ConfigStore(url: dir.appendingPathComponent("config.json"))
        try Data("{broken".utf8).write(to: store.url)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }
        let loaded = store.load()
        #expect(loaded.config == .defaults)
        #expect(loaded.error?.hasPrefix("config.json could not be read") == true)
        #expect(loaded.error?.contains("config.json.bad") == false)
        #expect(FileManager.default.fileExists(atPath: store.url.path))
    }

    @Test func refusesToSaveAnInvalidConfig() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ConfigStore(url: dir.appendingPathComponent("config.json"))
        var config = Config.defaults
        config.smoothing.holdSeconds = 500
        #expect(throws: ValidationError.self) { try store.save(config) }
        #expect(!FileManager.default.fileExists(atPath: store.url.path))
    }

    @Test func cleansUpTempFileWhenWriteFails() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ConfigStore(url: dir.appendingPathComponent("config.json"))
        let tempPath = dir.appendingPathComponent(".\(store.url.lastPathComponent).\(getpid()).tmp")
        try FileManager.default.createDirectory(at: tempPath, withIntermediateDirectories: true)

        var config = Config.defaults
        config.enabled = false
        #expect(throws: Error.self) { try store.save(config) }

        let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(contents.isEmpty, "No files should remain after failed atomic write (temp dir cleanup is attempted)")
        #expect(!FileManager.default.fileExists(atPath: store.url.path), "The target config.json should never exist when write fails")
    }
}

@Suite struct StateStoreTests {
    @Test func aMissingFileStartsEmptyWithoutAnError() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let loaded = StateStore(url: dir.appendingPathComponent("state.json")).load()
        #expect(loaded.state == DaemonState())
        #expect(loaded.error == nil)
    }

    @Test func aBrokenFileStartsEmptyIsMovedAsideAndReported() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = StateStore(url: dir.appendingPathComponent("state.json"))
        try Data("[]".utf8).write(to: store.url)
        let loaded = store.load()
        #expect(loaded.state == DaemonState())
        #expect(loaded.error?.hasPrefix("state.json could not be read") == true)
        #expect(loaded.error?.contains("state.json.bad") == true)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("state.json.bad").path))
        #expect(!FileManager.default.fileExists(atPath: store.url.path))
    }

    @Test func roundTripsReadableOnlyByRoot() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = StateStore(url: dir.appendingPathComponent("state.json"))
        let state = DaemonState(fans: [FanRange(minRPM: 1836, maxRPM: 5616)],
                                gpuSwitchOriginal: GPUSwitchValues(ac: 2, battery: 2), starts: [1000, 1010])
        try store.save(state)
        #expect(store.load().state == state)
        #expect(try permissions(of: store.url) == 0o600)
    }
}

@Suite struct HeartbeatTests {
    @Test func touchCreatesThenRefreshesTheFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("heartbeat")
        #expect(Heartbeat.age(url) == nil)
        #expect(Heartbeat.touch(url))
        #expect(try #require(Heartbeat.age(url)) < 2)
        #expect(try #require(Heartbeat.age(url, now: Date().addingTimeInterval(30))) > 29)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-60)], ofItemAtPath: url.path)
        #expect(try #require(Heartbeat.age(url)) > 59)
        #expect(Heartbeat.touch(url))
        #expect(try #require(Heartbeat.age(url)) < 2)
    }
}
