import XCTest
@testable import FitnessApp

final class GoalProgressPresentationTests: XCTestCase {
    func testTwoSufficientWindowsShowCurrentMinusPrevious() throws {
        let decrease = GoalWeightComparison(current: .init(value: 84.2, recordedDays: 3),
                                            previous: .init(value: 84.8, recordedDays: 3))
        XCTAssertEqual(try XCTUnwrap(decrease.changeKg), -0.6, accuracy: 0.0001)
        let increase = GoalWeightComparison(current: .init(value: 84.8, recordedDays: 7),
                                            previous: .init(value: 84.2, recordedDays: 5))
        XCTAssertEqual(try XCTUnwrap(increase.changeKg), 0.6, accuracy: 0.0001)
    }

    func testEitherWindowBelowThreeRecordedDaysDoesNotShowChange() {
        for counts in [(2, 7), (7, 2), (0, 0)] {
            let comparison = GoalWeightComparison(current: .init(value: 84.2, recordedDays: counts.0),
                                                  previous: .init(value: 84.8, recordedDays: counts.1))
            XCTAssertNil(comparison.changeKg)
        }
    }

    func testMissingAverageNeverFallsBackToReportedStartWeight() {
        XCTAssertNil(GoalWeightComparison(current: .init(value: nil, recordedDays: 3),
                                         previous: .init(value: 85, recordedDays: 7)).changeKg)
        XCTAssertNil(GoalWeightComparison(current: .init(value: 84, recordedDays: 7),
                                         previous: .init(value: nil, recordedDays: 3)).changeKg)
    }

    func testEqualAveragesAreAValidZeroChange() {
        XCTAssertEqual(GoalWeightComparison(current: .init(value: 84.2, recordedDays: 3),
                                           previous: .init(value: 84.2, recordedDays: 7)).changeKg, 0)
    }
}
