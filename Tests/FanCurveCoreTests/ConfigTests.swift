import Foundation
import Testing
@testable import FanCurveCore

@Suite struct ConfigTests {
    @Test func defaultsAreValid() throws {
        try Config.defaults.validate()
    }

    @Test func defaultsAreTheDocumentedCurves() {
        let curves = Config.defaults.curves
        #expect(curves.hotspot == Curve([CurvePoint(60, 0), CurvePoint(72, 30), CurvePoint(82, 70), CurvePoint(88, 100)]))
        #expect(curves.power == AuxCurve(enabled: true, curve: Curve([
            CurvePoint(23, 0), CurvePoint(38, 30), CurvePoint(58, 65), CurvePoint(78, 100),
        ])))
        #expect(curves.chassis == AuxCurve(enabled: false, curve: Curve([
            CurvePoint(42, 0), CurvePoint(46, 35), CurvePoint(50, 75), CurvePoint(53, 100),
        ])))
        #expect(Config.defaults.smoothing == Smoothing(upPercentPerSecond: 25, holdSeconds: 20, downPercentPerSecond: 2, deadbandPercent: 3))
        #expect(Config.defaults.enabled)
        #expect(!Config.defaults.gpuPolicy.enabled)
        #expect(Config.defaults.version == 2)
    }

    @Test func roundTripsThroughJSON() throws {
        #expect(try Config.decode(Config.defaults.encoded()) == Config.defaults)
    }

    @Test func auxCurveIsAnObjectWithEnabledAndPoints() throws {
        let data = try JSONEncoder().encode(AuxCurve(enabled: false, curve: Curve([CurvePoint(42, 0), CurvePoint(53, 100)])))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object.count == 2)
        #expect(object["enabled"] as? Bool == false)
        #expect(object["points"] as? [[Double]] == [[42, 0], [53, 100]])
    }

    @Test func rejectsVersionOne() {
        var config = Config.defaults
        config.version = 1
        #expect(throws: ValidationError(message: "unknown config version: 1")) { try config.validate() }
    }

    @Test func rejectsInvalidHotspotCurve() {
        var config = Config.defaults
        config.curves.hotspot = Curve([CurvePoint(80, 50), CurvePoint(90, 10)])
        #expect(throws: ValidationError.self) { try config.validate() }
    }

    @Test func validatesSwitchedOffCurvesToo() {
        var config = Config.defaults
        config.curves.chassis.curve = Curve([CurvePoint(50, 0)])
        #expect(!config.curves.chassis.enabled)
        #expect(throws: ValidationError.self) { try config.validate() }
    }

    @Test func rejectsSmoothingOutOfRange() {
        var config = Config.defaults
        config.smoothing.downPercentPerSecond = 0.1
        let tooSlow = ValidationError(.smoothingOutOfRange(field: .down, value: 0.1, range: 0.5...50))
        #expect(throws: tooSlow) { try config.validate() }
        #expect(tooSlow.message == "downPercentPerSecond: 0.1 outside 0.5…50.0")
        config = Config.defaults
        config.smoothing.holdSeconds = 500
        #expect(throws: ValidationError.self) { try config.validate() }
        config = Config.defaults
        config.smoothing.deadbandPercent = .infinity
        #expect(throws: ValidationError.self) { try config.validate() }
    }

    @Test func eachFieldAcceptsExactlyItsRange() {
        func smoothing(_ field: SmoothingField, _ value: Double) -> Smoothing {
            var smoothing = Smoothing()
            switch field {
            case .up: smoothing.upPercentPerSecond = value
            case .hold: smoothing.holdSeconds = value
            case .down: smoothing.downPercentPerSecond = value
            case .deadband: smoothing.deadbandPercent = value
            }
            return smoothing
        }
        #expect(SmoothingField.allCases.map { Smoothing.range(for: $0) } == [1...100, 0...120, 0.5...50, 0...10])
        for field in SmoothingField.allCases {
            let range = Smoothing.range(for: field)
            #expect(throws: Never.self) { try smoothing(field, range.lowerBound).validate() }
            #expect(throws: Never.self) { try smoothing(field, range.upperBound).validate() }
            let above = range.upperBound + 1
            #expect(throws: ValidationError(.smoothingOutOfRange(field: field, value: above, range: range))) {
                try smoothing(field, above).validate()
            }
        }
    }

    /// Messages name a field by its key, so a `fancurvectl config set` error names what the user edits.
    @Test func smoothingFieldsAreTheConfigKeys() throws {
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(Smoothing())) as? [String: Any])
        #expect(Set(object.keys) == Set(SmoothingField.allCases.map { $0.rawValue }))
    }

    @Test func unreadableJSONBecomesValidationError() {
        #expect(throws: ValidationError.self) { try Config.decode(Data("{not json".utf8)) }
        #expect(throws: ValidationError.self) { try Config.decode(Data("{}".utf8)) }
    }

    @Test func aParseErrorNamesTheKeyInsteadOfSwiftsDump() throws {
        #expect(throws: ValidationError(message: "the config does not parse: version is missing")) {
            try Config.decode(Data("{}".utf8))
        }
        var object = try #require(try JSONSerialization.jsonObject(with: Config.defaults.encoded()) as? [String: Any])
        var smoothing = try #require(object["smoothing"] as? [String: Any])
        smoothing["holdSeconds"] = nil
        object["smoothing"] = smoothing
        #expect(throws: ValidationError(message: "the config does not parse: smoothing.holdSeconds is missing")) {
            try Config.decode(JSONSerialization.data(withJSONObject: object))
        }
        let mismatch = try #require(throws: ValidationError.self) { try Config.decode(Data(#"{"version": "2"}"#.utf8)) }
        #expect(mismatch.message.hasPrefix("the config does not parse: version: "))
        let garbage = try #require(throws: ValidationError.self) { try Config.decode(Data("{not json".utf8)) }
        #expect(garbage.message.hasPrefix("the config does not parse: "))
        #expect(!garbage.message.contains("DecodingError"))
    }
}
