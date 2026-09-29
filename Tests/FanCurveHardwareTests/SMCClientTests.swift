import Foundation
import Testing
@testable import FanCurveHardware

@Suite struct SMCLayoutTests {
    @Test func paramStructMatchesKernelLayout() {
        #expect(MemoryLayout<SMCParamStruct>.size == 80)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.keyInfo) == 28)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.result) == 40)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.data8) == 42)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.data32) == 44)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.bytes) == 48)
    }
}

@Suite struct SMCWriteSizeTests {
    @Test func aValueLongerThanOneCallHasItsOwnError() {
        func failure(_ count: Int, keySize: Int) -> String? {
            do {
                try SMCClient.checkWriteSize(count, keySize: keySize)
                return nil
            } catch {
                return "\(error)"
            }
        }
        #expect(failure(40, keySize: 40) == "an SMC call carries at most 32 bytes, got 40")
        #expect(failure(2, keySize: 4) == "key takes 4 bytes, got 2")
        #expect(failure(4, keySize: 4) == nil)
    }
}

/// Talks to the real SMC. Run with: FANCURVE_HW_TESTS=1 swift test --filter SMCHardwareTests
@Suite struct SMCHardwareTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FANCURVE_HW_TESTS"] == "1"))
    func readsKeysWithoutRoot() throws {
        let smc = try SMCClient()
        #expect(try smc.keyCount() > 50)
        #expect(try smc.readValue(SMCKey("FNum")!) == 2)
        #expect(try smc.keyInfo(SMCKey("F0Ac")!).type == "flt ")
    }
}
