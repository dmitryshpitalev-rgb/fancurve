import Foundation
import Testing
@testable import FanCurveCore

@Suite struct ReplayTests {
    static let profile = HardwareProfile(
        model: "MacBookPro16,1",
        cpuTemps: ["TC1C", "TC2C"],
        gpuTemps: ["TGDD"],
        gpuIoregTemp: "ioreg.gpu.temp",
        chassisTemps: ["Ts0P"],
        cpuPower: "PCPC",
        gpuPower: "ioreg.gpu.power",
        gpuActiveRule: Threshold(column: "PG0R", above: 1.0),
        fanActual: ["F0Ac", "F1Ac"],
        fanMode: ["F0Md", "F1Md"],
        fanTarget: ["F0Tg", "F1Tg"],
        fans: [FanRange(minRPM: 2000, maxRPM: 5400), FanRange(minRPM: 2000, maxRPM: 5400)]
    )

    @Test func parsesTraceWithEmptyCells() throws {
        let trace = try Trace.parse(csv: "t,TC1C,F0Ac\n0.0,55.5,\n0.5,,2100\n")
        #expect(trace.columns == ["t", "TC1C", "F0Ac"])
        #expect(trace.rows == [[0, 55.5, nil], [0.5, nil, 2100]])
    }

    @Test func rejectsMalformedTraces() {
        #expect(throws: ValidationError.self) { try Trace.parse(csv: "") }
        #expect(throws: ValidationError.self) { try Trace.parse(csv: "time,TC1C\n0,50\n") }
        #expect(throws: ValidationError.self) { try Trace.parse(csv: "t,TC1C\n0,50,1\n") }
        #expect(throws: ValidationError.self) { try Trace.parse(csv: "t,TC1C\n,50\n") }
    }

    @Test func aCellThatIsNotANumberIsRefusedWithItsPlace() {
        #expect(throws: ValidationError(message: "line 3, column TC1C: \"n/a\" is not a number")) {
            try Trace.parse(csv: "t,TC1C\n0,50\n0.5,n/a\n")
        }
    }

    @Test func rejectsNonFiniteTraceTime() {
        // Double("nan") and Double("inf") both parse; a non-finite first t would freeze every
        // channel filter forever (they'd never see time advance past it).
        #expect(throws: ValidationError.self) { try Trace.parse(csv: "t,TC1C\nnan,50\n") }
        #expect(throws: ValidationError.self) { try Trace.parse(csv: "t,TC1C\ninf,50\n") }
    }

    @Test func profileBuildsChannelsFromNamedReadings() {
        let values: [String: Double] = [
            "TC1C": 71, "TC2C": 74, "TGDD": 60, "ioreg.gpu.temp": 58, "Ts0P": 36,
            "PCPC": 30, "ioreg.gpu.power": 8, "PG0R": 7.4, "F0Ac": 2100, "F1Ac": 2150,
        ]
        let input = Self.profile.tickInput(time: 1) { values[$0] }
        #expect(input.channels == PerChannel(cpu: 74, gpu: 60, chassis: 36, power: 38))
        #expect(input.gpuActive)
        #expect(input.fanRPM == [2100, 2150])
    }

    @Test func nonFiniteTachometerReadsAsMissing() {
        // A NaN or infinite F0Ac/F1Ac must read as "no reading", not as a number: a non-finite
        // percent later traps `Int(...)` in `FanRange.rpm(forPercent:)` and fails to encode.
        let values: [String: Double] = ["TC1C": 50, "F0Ac": Double.nan, "F1Ac": Double.infinity]
        let input = Self.profile.tickInput(time: 0) { values[$0] }
        #expect(input.fanRPM == [nil, nil])
    }

    @Test func radeonOffDropsGPUPower() {
        let values: [String: Double] = ["TC1C": 50, "PCPC": 10, "ioreg.gpu.power": 8, "PG0R": 0.13]
        let input = Self.profile.tickInput(time: 1) { values[$0] }
        #expect(!input.gpuActive)
        #expect(input.channels.power == 10)
    }

    @Test func unreadableGPUActiveRuleColumnIsTreatedAsActive() {
        // The rule's column isn't present in this reading at all (an unreadable rail), as opposed
        // to being present and reading below threshold. That must not look like a sleeping Radeon.
        let values: [String: Double] = ["TC1C": 50, "PCPC": 10]
        let input = Self.profile.tickInput(time: 0) { values[$0] }
        #expect(input.gpuActive)
    }

    @Test func nonFiniteGPUActiveRuleColumnIsTreatedAsActive() {
        // A NaN reading in the rule's column (as opposed to the column being absent) must not
        // read as a sleeping Radeon either: NaN compares false against the threshold either way,
        // so an unguarded `>` would silently say "asleep" for what is actually an unreadable tick.
        let values: [String: Double] = ["TC1C": 50, "PCPC": 10, "PG0R": Double.nan]
        let input = Self.profile.tickInput(time: 0) { values[$0] }
        #expect(input.gpuActive)
    }

    @Test func withoutRuleRadeonIsActiveWhenItsTemperatureReads() {
        var profile = Self.profile
        profile.gpuActiveRule = nil
        let withGPU: [String: Double] = ["TC1C": 50, "ioreg.gpu.temp": 57]
        let withoutGPU: [String: Double] = ["TC1C": 50]
        #expect(profile.tickInput(time: 0) { withGPU[$0] }.gpuActive)
        #expect(!profile.tickInput(time: 0) { withoutGPU[$0] }.gpuActive)
    }

    @Test func profileDecodesFromJSON() throws {
        let json = """
        {"model": "MacBookPro16,1", "cpuTemps": ["TCXC"], "gpuTemps": [], "gpuIoregTemp": "ioreg.gpu.temp",
         "chassisTemps": ["Ts0P"], "cpuPower": null, "gpuPower": null, "gpuActiveRule": null,
         "fanActual": ["F0Ac"], "fanMode": ["F0Md"], "fanTarget": ["F0Tg"], "fans": [{"minRPM": 2000, "maxRPM": 5400}]}
        """
        let profile = try JSONDecoder().decode(HardwareProfile.self, from: Data(json.utf8))
        #expect(profile.cpuPower == nil)
        #expect(profile.fanMode == ["F0Md"])
        #expect(profile.fanTarget == ["F0Tg"])
        // The keys the actuator writes are not optional.
        let noTargets = json.replacingOccurrences(of: #""fanTarget": ["F0Tg"], "#, with: "")
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(HardwareProfile.self, from: Data(noTargets.utf8)) }
    }

    @Test func replayRampsFansUnderSyntheticLoad() throws {
        // 10 s idle, then 20 s with the CPU at 90°C and 60 W.
        var csv = "t,TC1C,TC2C,TGDD,ioreg.gpu.temp,Ts0P,PCPC,ioreg.gpu.power,PG0R,F0Ac,F1Ac\n"
        for tick in 0..<60 {
            let t = Double(tick) * 0.5
            let loaded = t >= 10
            csv += "\(t),\(loaded ? 90 : 50),\(loaded ? 88 : 49),60,58,34,\(loaded ? 60 : 8),8,7.4,2000,2000\n"
        }
        let rows = Replay.run(trace: try Trace.parse(csv: csv), profile: Self.profile, config: .defaults)
        #expect(rows.count == 60)
        #expect(rows[0].mode == .active)
        #expect(rows[19].outputPercent == 0)
        #expect((rows[59].outputPercent ?? 0) > 90)
        #expect(rows[59].leading == .hotspot)
        #expect(rows[59].hotDie == .cpu)
        let lines = Replay.csv(rows).split(separator: "\n")
        #expect(lines.count == 61)
        #expect(lines[0] == "t,mode,cpu,gpu,chassis,power,leading,die,demand,output,rpm")
        #expect(lines[60].contains(",hotspot,cpu,"))
    }
}
