import XCTest
@testable import DailyTodo

final class LiveActivityPlannerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func snap(live: Bool, ageMinutes: Double?) -> ActivitySnapshot {
        ActivitySnapshot(
            isLive: live,
            startedAt: ageMinutes.map { now.addingTimeInterval(-$0 * 60) }
        )
    }

    private func action(
        userEnabled: Bool = true,
        systemEnabled: Bool = true,
        _ activities: [ActivitySnapshot]
    ) -> LiveActivityAction {
        LiveActivityPlanner.action(
            userEnabled: userEnabled,
            systemEnabled: systemEnabled,
            activities: activities,
            now: now
        )
    }

    func testDisabledByUserDoesNothingEvenWithLiveActivity() {
        XCTAssertEqual(action(userEnabled: false, [snap(live: true, ageMinutes: 5)]), .none)
    }

    func testDisabledBySystemDoesNothing() {
        XCTAssertEqual(action(systemEnabled: false, [snap(live: true, ageMinutes: 5)]), .none)
    }

    func testNoActivitiesStartsFresh() {
        XCTAssertEqual(action([]), .start)
    }

    func testOnlyDeadActivitiesStartsFresh() {
        // The zombie case: a system-ended activity still listed by ActivityKit
        // must not be mistaken for a running one.
        XCTAssertEqual(action([snap(live: false, ageMinutes: 30)]), .start)
    }

    func testFreshLiveActivityUpdates() {
        XCTAssertEqual(action([snap(live: true, ageMinutes: 30)]), .update)
    }

    func testOldLiveActivityRestarts() {
        XCTAssertEqual(action([snap(live: true, ageMinutes: 120)]), .restart)
    }

    func testUnknownStartDateRestarts() {
        XCTAssertEqual(action([snap(live: true, ageMinutes: nil)]), .restart)
    }

    func testExactlyMaxAgeRestarts() {
        XCTAssertEqual(action([snap(live: true, ageMinutes: 60)]), .restart)
    }

    func testDeadPlusFreshLiveUpdates() {
        XCTAssertEqual(action([snap(live: false, ageMinutes: 300), snap(live: true, ageMinutes: 10)]), .update)
    }
}
