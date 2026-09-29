import Foundation
import Testing
@testable import FanCurveCore

@Suite struct CurveTests {
    let curve = Curve([CurvePoint(60, 0), CurvePoint(72, 30), CurvePoint(82, 70), CurvePoint(88, 100)])

    @Test func clampsOutsideTheEnds() {
        #expect(curve.evaluate(20) == 0)
        #expect(curve.evaluate(60) == 0)
        #expect(curve.evaluate(88) == 100)
        #expect(curve.evaluate(105) == 100)
    }

    @Test func interpolatesLinearly() {
        #expect(curve.evaluate(66) == 15)
        #expect(curve.evaluate(72) == 30)
        #expect(curve.evaluate(77) == 50)
        #expect(curve.evaluate(85) == 85)
    }

    @Test func acceptsValidCurves() throws {
        try curve.validate(as: .hotspot)
        try Curve([CurvePoint(0, 0), CurvePoint(75, 100)]).validate(as: .power)
    }

    @Test func rejectsTooFewOrTooManyPoints() {
        #expect(throws: ValidationError.self) { try Curve([CurvePoint(60, 0)]).validate(as: .hotspot) }
        let nine = (0..<9).map { CurvePoint(Double(30 + $0 * 5), Double($0 * 10)) }
        #expect(throws: ValidationError.self) { try Curve(nine).validate(as: .hotspot) }
    }

    @Test func rejectsNonIncreasingX() {
        #expect(throws: ValidationError.self) {
            try Curve([CurvePoint(60, 0), CurvePoint(60, 50)]).validate(as: .hotspot)
        }
    }

    @Test func rejectsDecreasingY() {
        #expect(throws: ValidationError.self) {
            try Curve([CurvePoint(60, 50), CurvePoint(70, 40)]).validate(as: .hotspot)
        }
    }

    @Test func rejectsOutOfRangeValues() {
        #expect(throws: ValidationError.self) { try Curve([CurvePoint(10, 0), CurvePoint(70, 40)]).validate(as: .hotspot) }
        #expect(throws: ValidationError.self) { try Curve([CurvePoint(60, 0), CurvePoint(70, 140)]).validate(as: .hotspot) }
        #expect(throws: ValidationError.self) { try Curve([CurvePoint(0, 0), CurvePoint(250, 100)]).validate(as: .power) }
        #expect(throws: ValidationError.self) { try Curve([CurvePoint(60, .nan), CurvePoint(70, 40)]).validate(as: .hotspot) }
    }

    @Test func encodesPointsAsPairs() throws {
        let data = try JSONEncoder().encode(Curve([CurvePoint(60, 0), CurvePoint(88, 100)]))
        #expect(String(decoding: data, as: UTF8.self) == "[[60,0],[88,100]]")
        let decoded = try JSONDecoder().decode(Curve.self, from: Data("[[60,0],[88,100]]".utf8))
        #expect(decoded == Curve([CurvePoint(60, 0), CurvePoint(88, 100)]))
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Curve.self, from: Data("[[60,0,1]]".utf8)) }
    }

    @Test func limitsFollowTheCurveKind() {
        #expect(CurveLimits.xRange(for: .hotspot) == 20...110)
        #expect(CurveLimits.xRange(for: .chassis) == 20...110)
        #expect(CurveLimits.xRange(for: .power) == 0...200)
    }

    /// Messages name a curve by its key, so a `fancurvectl config set` error names what the user edits.
    @Test func messagesNameTheCurveByItsConfigKey() {
        #expect(ValidationError(.pointCount(curve: .power, count: 1)).message == "power: needs 2 to 8 points, has 1")
        #expect(ValidationError(.yDecreasing(curve: .hotspot, index: 3)).message == "hotspot: speed must not fall as x grows (point 3)")
    }

    @Test func validationErrorsCarryTheirKindAndCurve() {
        #expect(throws: ValidationError(.pointCount(curve: .hotspot, count: 1))) {
            try Curve([CurvePoint(60, 0)]).validate(as: .hotspot)
        }
        #expect(throws: ValidationError(.xOutOfRange(curve: .power, x: 250, range: 0...200))) {
            try Curve([CurvePoint(0, 0), CurvePoint(250, 100)]).validate(as: .power)
        }
        #expect(throws: ValidationError(.yOutOfRange(curve: .chassis, y: 140))) {
            try Curve([CurvePoint(40, 0), CurvePoint(50, 140)]).validate(as: .chassis)
        }
    }
}
