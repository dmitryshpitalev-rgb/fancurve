import Testing
@testable import FanCurveUI

@Suite struct MenuBarIconLevelTests {
    @Test func stableLevelStaysWhenPercentIsAlreadyWithinIt() {
        #expect(fanIconLevel(percent: 50, previous: 3) == 3)
        #expect(fanIconLevel(percent: 10, previous: 1) == 1)
    }

    @Test func risingNeedsAtLeastTwoPastTheBoundary() {
        #expect(fanIconLevel(percent: 41, previous: 2) == 2)
        #expect(fanIconLevel(percent: 42, previous: 2) == 3)
    }

    @Test func fallingNeedsAtLeastTwoPastTheBoundary() {
        #expect(fanIconLevel(percent: 39, previous: 3) == 3)
        #expect(fanIconLevel(percent: 38, previous: 3) == 2)
    }

    @Test func aBigJumpCrossesSeveralLevelsAtOnce() {
        #expect(fanIconLevel(percent: 85, previous: 1) == 5)
    }

    @Test func extremesMapToZeroAndFive() {
        #expect(fanIconLevel(percent: 0, previous: 0) == 0)
        #expect(fanIconLevel(percent: 100, previous: 0) == 5)
    }

    @Test func outOfRangePreviousIsClampedNotCrashed() {
        #expect(fanIconLevel(percent: 0, previous: -5) == 0)
        #expect(fanIconLevel(percent: 0, previous: 99) == 0)
        #expect(fanIconLevel(percent: 100, previous: -5) == 5)
        #expect(fanIconLevel(percent: 100, previous: 99) == 5)
    }
}
