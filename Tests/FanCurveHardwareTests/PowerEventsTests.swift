import Dispatch
import Testing
@testable import FanCurveHardware

@Suite struct PowerEventsTests {
    @Test func registersForSystemPowerNotifications() {
        let events = PowerEvents(willSleep: {}, didWake: {})
        #expect(events.start(queue: DispatchQueue(label: "test.power")))
    }

    /// Both sleep questions are answered, "will sleep" after the fans are handed back; an unanswered
    /// one holds every sleep up for 30 s.
    @Test func sleepIsAnsweredAfterWillSleepAndWakeCallsDidWake() {
        var events: [String] = []
        let power = PowerEvents(willSleep: { events.append("willSleep") }, didWake: { events.append("didWake") },
                                allowPowerChange: { _, id in events.append("allow \(id)") })
        power.handle(PowerEvents.canSystemSleep, UnsafeMutableRawPointer(bitPattern: 7))
        power.handle(PowerEvents.systemWillSleep, UnsafeMutableRawPointer(bitPattern: 8))
        power.handle(PowerEvents.systemHasPoweredOn, nil)
        power.handle(0xE000_0320, UnsafeMutableRawPointer(bitPattern: 9))  // will power on: nothing to answer
        #expect(events == ["allow 7", "willSleep", "allow 8", "didWake"])
    }
}
