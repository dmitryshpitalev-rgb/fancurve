import Foundation
import Testing
@testable import FanCurveHardware

@Suite struct PMSetTimeoutTests {
    @Test func aHungCallIsStoppedAtTheTimeout() {
        let start = Date()
        do {
            _ = try PMSet.run(["5"], executable: "/bin/sleep", timeout: 0.3)
            Issue.record("a 5 s call finished inside a 0.3 s timeout")
        } catch let error as PMSetError {
            guard case .timedOut = error else {
                Issue.record("expected a timeout, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error \(error)")
        }
        #expect(Date().timeIntervalSince(start) < 2)
    }

    @Test func aFailingCallStillReportsItsExitStatus() {
        do {
            _ = try PMSet.run(["-c", "echo nope; exit 3"], executable: "/bin/sh", timeout: 2)
            Issue.record("a failing call succeeded")
        } catch let error as PMSetError {
            guard case .failed(_, let status, let output) = error else {
                Issue.record("expected a failure, got \(error)")
                return
            }
            #expect(status == 3)
            #expect(output.contains("nope"))
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }
}
