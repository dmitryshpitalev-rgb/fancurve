import Foundation
import Testing
@testable import FanCurveCore

@Suite struct PerChannelTests {
    @Test func subscriptReadsAndWrites() {
        var values = PerChannel<Double?>.empty
        values[.chassis] = 41
        #expect(values.chassis == 41)
        #expect(values[.cpu] == nil)
    }

    @Test func mapTransformsEveryValue() {
        let doubled = PerChannel(cpu: 1, gpu: 2, chassis: 3, power: 4).map { $0 * 2 }
        #expect(doubled == PerChannel(cpu: 2, gpu: 4, chassis: 6, power: 8))
    }

    @Test func encodesAsObjectAndKeepsNils() throws {
        let values = PerChannel<Double?>(cpu: 70, gpu: nil, chassis: 38.5, power: 22)
        let data = try JSONEncoder().encode(values)
        #expect(try JSONDecoder().decode(PerChannel<Double?>.self, from: data) == values)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?.keys.contains("cpu") == true)
        #expect(object?.keys.contains("power") == true)
        #expect(object?["gpu"] is NSNull)
    }
}
