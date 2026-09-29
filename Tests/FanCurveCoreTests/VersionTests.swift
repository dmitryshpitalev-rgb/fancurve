import FanCurveCore
import Foundation
import Testing

@Suite struct VersionTests {
    @Test func theAppBundleCarriesTheSameVersion() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/FanCurveCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
        let plist = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: repoRoot.appendingPathComponent("packaging/Info.plist")), format: nil) as? [String: Any]
        #expect(plist?["CFBundleShortVersionString"] as? String == FanCurveVersion.string)
    }
}
