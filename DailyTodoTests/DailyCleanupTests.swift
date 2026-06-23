import XCTest
@testable import DailyTodo

final class DailyCleanupTests: XCTestCase {

    /// Fixed UTC calendar so day boundaries are deterministic regardless of host timezone.
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private let day0 = Date(timeIntervalSince1970: 0)          // 1970-01-01 00:00 UTC
    private var day1: Date { day0.addingTimeInterval(86_400) } // 1970-01-02 00:00 UTC
    private var day3: Date { day0.addingTimeInterval(3 * 86_400) }

    func testFirstRunDoesNotPurgeAndRecordsToday() {
        let result = DailyCleanup.decide(
            lastCleared: nil, now: day0.addingTimeInterval(9 * 3600), enabled: true, calendar: cal
        )
        XCTAssertFalse(result.purge)
        XCTAssertEqual(result.newMarker, day0)
    }

    func testSameDayDoesNotPurge() {
        let result = DailyCleanup.decide(
            lastCleared: day0.addingTimeInterval(9 * 3600),
            now: day0.addingTimeInterval(15 * 3600),
            enabled: true, calendar: cal
        )
        XCTAssertFalse(result.purge)
        XCTAssertEqual(result.newMarker, day0)
    }

    func testNewDayEnabledPurgesAndAdvances() {
        let result = DailyCleanup.decide(
            lastCleared: day0.addingTimeInterval(9 * 3600),
            now: day1.addingTimeInterval(10 * 3600),
            enabled: true, calendar: cal
        )
        XCTAssertTrue(result.purge)
        XCTAssertEqual(result.newMarker, day1)
    }

    func testNewDayDisabledDoesNotPurgeAndKeepsMarker() {
        let result = DailyCleanup.decide(
            lastCleared: day0.addingTimeInterval(9 * 3600),
            now: day1.addingTimeInterval(10 * 3600),
            enabled: false, calendar: cal
        )
        XCTAssertFalse(result.purge)
        XCTAssertEqual(result.newMarker, day0, "disabled keeps the marker so enabling later triggers a catch-up")
    }

    func testMissedMultipleDaysPurgesOnce() {
        let result = DailyCleanup.decide(
            lastCleared: day0.addingTimeInterval(9 * 3600),
            now: day3.addingTimeInterval(5 * 3600),
            enabled: true, calendar: cal
        )
        XCTAssertTrue(result.purge)
        XCTAssertEqual(result.newMarker, day3)
    }
}
