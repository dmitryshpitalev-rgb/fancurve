import FanCurveCore
import Foundation

func runSimulation(tracePath: String, profilePath: String, configPath: String?) -> Never {
    do {
        let trace = try Trace.parse(csv: String(contentsOfFile: tracePath, encoding: .utf8))
        let profile = try JSONDecoder().decode(HardwareProfile.self, from: Data(contentsOf: URL(fileURLWithPath: profilePath)))
        guard profile.fans.allSatisfy(\.isUsable) else {
            fail("simulate: every fan range in the profile needs 0 < minRPM < maxRPM <= 100000")
        }
        let config = try configPath.map { try Config.decode(Data(contentsOf: URL(fileURLWithPath: $0))) } ?? Config.defaults
        print(Replay.csv(Replay.run(trace: trace, profile: profile, config: config)), terminator: "")
        exit(0)
    } catch {
        fail("simulate: \(error)")
    }
}
