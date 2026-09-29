import Foundation
import Testing
@testable import FanCurveCore

@Suite struct ProtocolTests {
    @Test func modeEncodesKindAndReason() throws {
        let data = try JSONEncoder().encode(Mode.released(.sensorLoss))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: String]
        #expect(object == ["kind": "released", "reason": "sensorLoss"])
        for mode in [Mode.starting, .active, .disabled, .released(.sleep), .safe(.missingKeys)] {
            #expect(try JSONDecoder().decode(Mode.self, from: JSONEncoder().encode(mode)) == mode)
        }
    }

    @Test func unknownModeKindFailsToDecode() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Mode.self, from: Data(#"{"kind":"turbo"}"#.utf8))
        }
    }

    @Test func requestIsOneLineAndRoundTrips() throws {
        let request = Request(id: 7, cmd: .setConfig, args: RequestArgs(config: .defaults))
        let line = try LineCodec.encode(request)
        #expect(line.last == 0x0A)
        #expect(!line.dropLast().contains(0x0A))
        #expect(try LineCodec.decode(Request.self, from: line) == request)
    }

    @Test func requestUsesTheWireShape() throws {
        let line = try LineCodec.encode(Request(id: 1, cmd: .history, args: RequestArgs(seconds: 300)))
        let object = try JSONSerialization.jsonObject(with: line) as? [String: Any]
        #expect(object?["id"] as? Int == 1)
        #expect(object?["cmd"] as? String == "history")
        #expect((object?["args"] as? [String: Any])?["seconds"] as? Int == 300)
    }

    @Test func snapshotRoundTrips() throws {
        let snapshot = Snapshot(
            t: 1_789_000_000, mode: .active,
            raw: PerChannel(cpu: 71.5, gpu: nil, chassis: 38, power: 24),
            filtered: PerChannel(cpu: 70, gpu: nil, chassis: 37.9, power: 22),
            demand: DemandResult(hotspot: 27.5, power: 6, chassis: nil, hotDie: .cpu, leading: .hotspot, percent: 27.5),
            outputPercent: 27.5,
            fans: [FanState(actualRPM: 2950, targetRPM: 2935, minRPM: 2000, maxRPM: 5400)],
            gpuPolicy: GPUPolicyState(enabled: true, acSwitch: 1, batterySwitch: 2),
            configError: nil,
            smcError: "SMC error 0x86"
        )
        #expect(try LineCodec.decode(Snapshot.self, from: LineCodec.encode(snapshot)) == snapshot)
    }

    @Test func aFanStateCarriesItsRange() {
        let fan = FanState(actualRPM: 2950, targetRPM: 2935, minRPM: 1836, maxRPM: 5616)
        #expect(fan.range == FanRange(minRPM: 1836, maxRPM: 5616))
    }

    @Test func demandEncodesCurveNamesAndTheHotDie() throws {
        let data = try JSONEncoder().encode(DemandResult(hotspot: 40, power: nil, chassis: nil, hotDie: .gpu, leading: .hotspot, percent: 40))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["hotDie"] as? String == "gpu")
        #expect(object["leading"] as? String == "hotspot")
        #expect(object["hotspot"] as? Double == 40)
        #expect(object["percent"] as? Double == 40)
    }

    @Test func errorResponseDecodesAsAnyPayloadType() throws {
        let line = try LineCodec.encode(Response<EmptyData>.failure(id: 3, "hotspot: speed must not fall as x grows (point 3)"))
        let decoded = try LineCodec.decode(Response<Snapshot>.self, from: line)
        #expect(decoded.id == 3)
        #expect(!decoded.ok)
        #expect(decoded.data == nil)
        #expect(decoded.error == "hotspot: speed must not fall as x grows (point 3)")
    }

    @Test func historyResponseRoundTrips() throws {
        let sample = Sample(t: 10, cpu: 60, gpu: nil, chassis: 35, power: 15, demandPercent: 0,
                            leading: .hotspot, fanRPM: [2000, nil], mode: .released(.sleep))
        let response = Response.success(id: 4, [sample])
        #expect(try LineCodec.decode(Response<[Sample]>.self, from: LineCodec.encode(response)) == response)
    }
}
