import XCTest
import SwiftData
@testable import DailyTodo

final class StashTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: TaskItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    // MARK: - StashDuration

    func testTomorrowReturnsLocalMidnightNextDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let now = Date(timeIntervalSince1970: 1_700_000_000) // arbitrary fixed instant
        let date = StashDuration.tomorrow.returnDate(now: now, calendar: cal)
        let expected = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
        XCTAssertEqual(date, expected)
    }

    func testNextWeekReturnsLocalMidnightSevenDaysOut() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let date = StashDuration.nextWeek.returnDate(now: now, calendar: cal)
        let expected = cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: now))!
        XCTAssertEqual(date, expected)
    }

    func testNeverHasNoReturnDate() {
        XCTAssertNil(StashDuration.never.returnDate(now: Date(), calendar: .current))
    }

    // MARK: - mutations

    func testStashSetsFlagAndReturnDate() throws {
        let context = try makeContext()
        let task = TaskItem(title: "Packages")
        context.insert(task)
        try context.save()
        let due = Date(timeIntervalSince1970: 1_700_100_000)

        TaskActions.stash(task, until: due, in: context)

        XCTAssertTrue(task.isStashed)
        XCTAssertEqual(task.stashReturnDate, due)
    }

    func testUnstashClearsStateAndLandsAtBottomOfOpenGroup() throws {
        let context = try makeContext()
        let a = TaskItem(title: "A", sortOrder: 0)
        let b = TaskItem(title: "B", sortOrder: 1)
        let stashed = TaskItem(title: "S", sortOrder: 5, isStashed: true,
                               stashReturnDate: Date(timeIntervalSince1970: 1))
        [a, b, stashed].forEach(context.insert)
        try context.save()

        TaskActions.unstash(stashed, in: context)

        XCTAssertFalse(stashed.isStashed)
        XCTAssertNil(stashed.stashReturnDate)
        // Lands after the highest open sortOrder (1) -> 2.
        XCTAssertEqual(stashed.sortOrder, 2)
    }

    func testClearStashRemovesOnlyStashedAndReturnsSnapshots() throws {
        let context = try makeContext()
        let open = TaskItem(title: "Open")
        let s1 = TaskItem(title: "S1", isStashed: true)
        let s2 = TaskItem(title: "S2", isStashed: true,
                          stashReturnDate: Date(timeIntervalSince1970: 10))
        [open, s1, s2].forEach(context.insert)
        try context.save()

        let snaps = TaskActions.clearStash(in: context)

        XCTAssertEqual(Set(snaps.map(\.title)), ["S1", "S2"])
        XCTAssertEqual(context.allTasks().map(\.title), ["Open"])
    }

    func testSnapshotRoundTripsStashState() throws {
        let context = try makeContext()
        let due = Date(timeIntervalSince1970: 12345)
        let task = TaskItem(title: "S", isStashed: true, stashReturnDate: due)
        context.insert(task)
        try context.save()

        let snaps = TaskActions.delete([task], in: context)
        XCTAssertTrue(context.allTasks().isEmpty)
        TaskActions.restore(snaps, in: context)

        let restored = context.allTasks().first
        XCTAssertEqual(restored?.isStashed, true)
        XCTAssertEqual(restored?.stashReturnDate, due)
    }
}

extension StashTests {

    func testDueReturnsOnlyPastDatedStashedItems() {
        let now = Date(timeIntervalSince1970: 1_000)
        let past   = TaskItem(title: "Past", isStashed: true,
                              stashReturnDate: Date(timeIntervalSince1970: 500))
        let future = TaskItem(title: "Future", isStashed: true,
                              stashReturnDate: Date(timeIntervalSince1970: 5_000))
        let never  = TaskItem(title: "Never", isStashed: true, stashReturnDate: nil)
        let open   = TaskItem(title: "Open")

        let due = StashReturn.due([past, future, never, open], now: now)

        XCTAssertEqual(due.map(\.title), ["Past"])
    }

    func testRunIfNeededUnstashesDueItemsToBottomOfOpenGroup() throws {
        let context = try makeContext()
        let now = Date(timeIntervalSince1970: 1_000)
        let open = TaskItem(title: "Open", sortOrder: 0)
        let due  = TaskItem(title: "Due", isStashed: true,
                            stashReturnDate: Date(timeIntervalSince1970: 500))
        let notYet = TaskItem(title: "NotYet", isStashed: true,
                              stashReturnDate: Date(timeIntervalSince1970: 5_000))
        [open, due, notYet].forEach(context.insert)
        try context.save()

        let count = StashReturn.runIfNeeded(in: context, now: now)

        XCTAssertEqual(count, 1)
        XCTAssertFalse(due.isStashed)
        XCTAssertEqual(due.sortOrder, 1)          // bottom of open group
        XCTAssertTrue(notYet.isStashed)           // future item untouched
        XCTAssertEqual(context.orderedTasks().map(\.title), ["Open", "Due"])
    }
}

extension StashTests {

    func testOrderedTasksExcludesStashed() throws {
        let context = try makeContext()
        context.insert(TaskItem(title: "Today"))
        context.insert(TaskItem(title: "Stashed", isStashed: true))
        try context.save()

        XCTAssertEqual(context.orderedTasks().map(\.title), ["Today"])
    }

    func testStashedTasksSortedSoonestFirstNeverLast() throws {
        let context = try makeContext()
        let never = TaskItem(title: "Never", isStashed: true, stashReturnDate: nil)
        let soon  = TaskItem(title: "Soon", isStashed: true,
                             stashReturnDate: Date(timeIntervalSince1970: 100))
        let later = TaskItem(title: "Later", isStashed: true,
                             stashReturnDate: Date(timeIntervalSince1970: 500))
        let open  = TaskItem(title: "Open")
        [never, soon, later, open].forEach(context.insert)
        try context.save()

        XCTAssertEqual(context.stashedTasks().map(\.title), ["Soon", "Later", "Never"])
    }

    func testReturnLabelFormatting() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
        let inFive   = cal.date(byAdding: .day, value: 5, to: cal.startOfDay(for: now))!

        XCTAssertEqual(StashFormatting.returnLabel(for: nil, now: now, calendar: cal), "Someday")
        XCTAssertEqual(StashFormatting.returnLabel(for: tomorrow, now: now, calendar: cal), "Back tomorrow")
        XCTAssertEqual(StashFormatting.returnLabel(for: inFive, now: now, calendar: cal), "Back in 5 days")
    }
}
