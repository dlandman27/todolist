import XCTest
@testable import DailyTodo

final class RepeatCadenceTests: XCTestCase {

    /// Fixed UTC calendar so weekday/day-of-month math is deterministic.
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// 1970-01-01 = Thursday (weekday 5), day-of-month 1.
    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(n) * 86_400) }

    // weekly

    func testWeeklyScheduledOnMatchingWeekday() {
        let cadence = RepeatCadence.weekly([5])            // Thursday
        XCTAssertTrue(cadence.isScheduled(on: day(0), calendar: cal))   // Thu
        XCTAssertFalse(cadence.isScheduled(on: day(1), calendar: cal))  // Fri
    }

    // monthly

    func testMonthlyScheduledOnMatchingDayOfMonth() {
        let cadence = RepeatCadence.monthly([1])
        XCTAssertTrue(cadence.isScheduled(on: day(0), calendar: cal))   // Jan 1
        XCTAssertFalse(cadence.isScheduled(on: day(1), calendar: cal))  // Jan 2
    }

    func testMonthlyDayAbsentFromMonthNeverFires() {
        // Feb 1970 has no 31st. day(58) = 1970-02-28, day(59) = 1970-03-01.
        let cadence = RepeatCadence.monthly([31])
        for offset in 31...58 {   // all of February
            XCTAssertFalse(cadence.isScheduled(on: day(offset), calendar: cal))
        }
    }

    // summary

    func testWeeklySummaryListsDaysInWeekOrder() {
        // 2=Mon, 4=Wed, 6=Fri
        XCTAssertEqual(RepeatCadence.weekly([6, 2, 4]).summary(), "Mon · Wed · Fri")
    }

    func testMonthlySummarySingleDayOrdinal() {
        XCTAssertEqual(RepeatCadence.monthly([1]).summary(), "1st of the month")
    }

    func testMonthlySummaryMultipleDays() {
        XCTAssertEqual(RepeatCadence.monthly([1, 15]).summary(), "1st · 15th")
    }

    // codable

    func testCodableRoundTrip() {
        let cadence = RepeatCadence.weekly([2, 4, 6])
        let encoded = cadence.encoded()
        XCTAssertNotNil(encoded)
        XCTAssertEqual(RepeatCadence.decode(from: encoded!), cadence)
    }

    func testDecodeGarbageReturnsNil() {
        XCTAssertNil(RepeatCadence.decode(from: "not json"))
    }
}
