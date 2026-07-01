import XCTest
import SwiftData
@testable import DailyTodo

final class RepeatSpawnerTests: XCTestCase {

    func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: TaskItem.self, RepeatRule.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    func testRepeatRuleCadenceAccessorRoundTrips() throws {
        let context = try makeContext()
        let rule = RepeatRule(name: "Water plants")
        context.insert(rule)
        XCTAssertNil(rule.cadence)

        let cadence = RepeatCadence.weekly([2, 5])
        rule.cadence = cadence
        try context.save()

        XCTAssertEqual(rule.cadence, cadence)
        XCTAssertNotNil(rule.cadenceData)
    }

    func testTaskItemCarriesRepeatRuleID() {
        let id = UUID()
        let task = TaskItem(title: "Water plants", repeatRuleID: id)
        XCTAssertEqual(task.repeatRuleID, id)
        XCTAssertNil(TaskItem(title: "Hand-added").repeatRuleID)
    }

    private var utcCal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    /// day(n) at UTC midnight. day(0) = 1970-01-01 = Thursday (weekday 5).
    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(n) * 86_400) }

    func testFiresOnScheduledDayWhenNeverSpawnedAndNoInstance() {
        let cadence = RepeatCadence.weekly([5])  // Thursday; day(0) is Thursday
        XCTAssertTrue(RepeatSpawner.shouldSpawn(
            cadence: cadence, lastSpawnedDay: nil,
            now: day(0).addingTimeInterval(9 * 3600), hasOpenInstance: false, calendar: utcCal))
    }

    func testDoesNotFireOnUnscheduledDay() {
        let cadence = RepeatCadence.weekly([5])  // Thursday
        XCTAssertFalse(RepeatSpawner.shouldSpawn(
            cadence: cadence, lastSpawnedDay: nil,
            now: day(1), hasOpenInstance: false, calendar: utcCal))  // Friday
    }

    func testSuppressedWhenOpenInstanceExists() {
        let cadence = RepeatCadence.weekly([5])
        XCTAssertFalse(RepeatSpawner.shouldSpawn(
            cadence: cadence, lastSpawnedDay: nil,
            now: day(0), hasOpenInstance: true, calendar: utcCal))
    }

    func testSuppressedWhenAlreadySpawnedToday() {
        let cadence = RepeatCadence.weekly([5])
        XCTAssertFalse(RepeatSpawner.shouldSpawn(
            cadence: cadence, lastSpawnedDay: day(0),
            now: day(0).addingTimeInterval(20 * 3600), hasOpenInstance: false, calendar: utcCal))
    }

    func testBrandNewRuleDoesNotFireRetroactively() {
        // Today is Friday day(1); Thursday day(0) was scheduled but the rule didn't exist then.
        let cadence = RepeatCadence.weekly([5])  // Thursday
        XCTAssertFalse(RepeatSpawner.shouldSpawn(
            cadence: cadence, lastSpawnedDay: nil,
            now: day(1), hasOpenInstance: false, calendar: utcCal))
    }

    func testSingleCatchUpForMissedScheduledDay() {
        // Last spawned day(0) Thu; now is day(9) (next-next Saturday). A Thursday
        // (day(7)) was missed → catch up once.
        let cadence = RepeatCadence.weekly([5])  // Thursday
        XCTAssertTrue(RepeatSpawner.shouldSpawn(
            cadence: cadence, lastSpawnedDay: day(0),
            now: day(9), hasOpenInstance: false, calendar: utcCal))
    }
}
