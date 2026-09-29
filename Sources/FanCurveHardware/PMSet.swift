import Foundation

enum PMSetError: Error, CustomStringConvertible {
    case failed(arguments: [String], status: Int32, output: String)
    case timedOut(arguments: [String], seconds: Double)

    var description: String {
        switch self {
        case .failed(let arguments, let status, let output):
            let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return "pmset \(arguments.joined(separator: " ")) exited \(status): \(text)"
        case .timedOut(let arguments, let seconds):
            return "pmset \(arguments.joined(separator: " ")) did not finish in \(seconds) s and was stopped"
        }
    }
}

/// `pmset` for the per-power-source `gpuswitch` setting: 0 integrated, 1 discrete, 2 automatic.
public enum PMSet {
    /// Longest a pmset call may take. pmset runs on the daemon's engine queue (the 30 s status
    /// refresh and the auto-graphics switch), where a hung call holds up fan control: 2 s plus the
    /// 1 s it takes to stop it, so one call stays inside the watchdog's 5 s limit; a graphics switch
    /// makes two or three in a row and may not, in which case the watchdog hands the fans to macOS
    /// until the next tick re-asserts them.
    static let timeoutSeconds = 2.0

    /// `gpuswitch` from each section of `pmset -g custom` output.
    static func parseGPUSwitch(_ text: String) -> (ac: Int?, battery: Int?) {
        var section = ""
        var ac: Int?
        var battery: Int?
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasSuffix(":") {
                section = String(line.dropLast())
                continue
            }
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 2, fields[0] == "gpuswitch", let value = Int(fields[1]) else { continue }
            if section == "AC Power" { ac = value }
            if section == "Battery Power" { battery = value }
        }
        return (ac, battery)
    }

    public static func readGPUSwitch() throws -> (ac: Int?, battery: Int?) {
        parseGPUSwitch(try run(["-g", "custom"]))
    }

    /// Needs root.
    public static func setGPUSwitch(ac: Int, battery: Int) throws {
        _ = try run(["-c", "gpuswitch", String(ac)])
        _ = try run(["-b", "gpuswitch", String(battery)])
    }

    /// Runs /usr/bin/pmset and returns stdout and stderr together. Both pipe ends are closed
    /// explicitly and the call drains its own autorelease pool, so a long-running caller does not
    /// pile up descriptors. `executable` is replaced only in tests.
    static func run(_ arguments: [String], executable: String = "/usr/bin/pmset",
                    timeout: Double = PMSet.timeoutSeconds) throws -> String {
        try autoreleasepool {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            defer {
                try? pipe.fileHandleForReading.close()
                try? pipe.fileHandleForWriting.close()
            }
            let finished = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in finished.signal() }
            try process.run()
            try? pipe.fileHandleForWriting.close()
            // pmset prints a few KB, far below the pipe buffer, so waiting for the exit before
            // reading cannot deadlock. A call still running at the timeout is stopped.
            if finished.wait(timeout: .now() + timeout) == .timedOut {
                process.terminate()
                _ = finished.wait(timeout: .now() + 1)
                throw PMSetError.timedOut(arguments: arguments, seconds: timeout)
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: data, as: UTF8.self)
            guard process.terminationStatus == 0 else {
                throw PMSetError.failed(arguments: arguments, status: process.terminationStatus, output: output)
            }
            return output
        }
    }
}
