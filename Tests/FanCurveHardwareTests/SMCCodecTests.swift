import Testing
@testable import FanCurveHardware

@Suite struct SMCKeyTests {
    @Test func encodesFourCharacterNames() {
        #expect(SMCKey("F0Mn")?.code == 0x4630_4D6E)
        #expect(SMCKey("FS! ")?.name == "FS! ")
        #expect(SMCKey(code: 0x234B_4559).name == "#KEY")
    }

    @Test func rejectsWrongLengthOrNonASCII() {
        #expect(SMCKey("F0M") == nil)
        #expect(SMCKey("F0Mnn") == nil)
        #expect(SMCKey("Ф0M") == nil)
    }
}

@Suite struct SMCCodecTests {
    // Vectors from Macs Fan Control logs on MacBookPro16,1:
    // "SMCWriteKey F0Tg 0088a545" = 5297 RPM, "F1Tg 00489945" = 4905 RPM.
    @Test func decodesLittleEndianFloat() {
        #expect(SMCCodec.decode(type: "flt ", bytes: [0x00, 0x88, 0xA5, 0x45]) == 5297)
        #expect(SMCCodec.decode(type: "flt ", bytes: [0x00, 0x48, 0x99, 0x45]) == 4905)
    }

    @Test func encodesLittleEndianFloat() {
        #expect(SMCCodec.encode(type: "flt ", value: 5297, size: 4) == [0x00, 0x88, 0xA5, 0x45])
    }

    // smcFanControl issue #96: 3500 RPM in fpe2 is 0x36b0.
    @Test func roundTripsFpe2() {
        #expect(SMCCodec.encode(type: "fpe2", value: 3500, size: 2) == [0x36, 0xB0])
        #expect(SMCCodec.decode(type: "fpe2", bytes: [0x36, 0xB0]) == 3500)
    }

    @Test func decodesSignedFixedPoint() {
        #expect(SMCCodec.decode(type: "sp78", bytes: [0x3C, 0x80]) == 60.5)
        #expect(SMCCodec.decode(type: "sp78", bytes: [0xFF, 0x00]) == -1)
    }

    @Test func decodesIntegers() {
        #expect(SMCCodec.decode(type: "ui8 ", bytes: [0x01]) == 1)
        #expect(SMCCodec.decode(type: "flag", bytes: [0x01]) == 1)
        #expect(SMCCodec.decode(type: "si8 ", bytes: [0xFF]) == -1)
        #expect(SMCCodec.decode(type: "ui16", bytes: [0x01, 0x02]) == 258)
        #expect(SMCCodec.decode(type: "si16", bytes: [0xFF, 0xFE]) == -2)
        #expect(SMCCodec.decode(type: "ui32", bytes: [0x00, 0x00, 0x01, 0x00]) == 256)
    }

    @Test func encodesIntegersPaddedToKeySize() {
        #expect(SMCCodec.encode(type: "ui8 ", value: 1, size: 1) == [0x01])
        #expect(SMCCodec.encode(type: "ui8 ", value: 1, size: 2) == [0x01, 0x00])
        #expect(SMCCodec.encode(type: "ui16", value: 3, size: 2) == [0x00, 0x03])
        #expect(SMCCodec.encode(type: "ui32", value: 256, size: 4) == [0x00, 0x00, 0x01, 0x00])
    }

    @Test func rejectsUnsupportedOrInvalidInput() {
        #expect(SMCCodec.decode(type: "{fds", bytes: [0, 0, 0, 0]) == nil)
        #expect(SMCCodec.decode(type: "flt ", bytes: [0, 0]) == nil)
        #expect(SMCCodec.encode(type: "ui8 ", value: 256, size: 1) == nil)
        #expect(SMCCodec.encode(type: "ui8 ", value: 1.5, size: 1) == nil)
        #expect(SMCCodec.encode(type: "flt ", value: 1, size: 2) == nil)
        #expect(SMCCodec.encode(type: "flt ", value: .nan, size: 4) == nil)
        #expect(SMCCodec.encode(type: "ch8*", value: 1, size: 4) == nil)
    }
}
