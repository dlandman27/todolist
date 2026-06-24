import XCTest
import SwiftData
@testable import DailyTodo

final class TaskActionsTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: TaskItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    func testClearCompletedRemovesOnlyDoneTasks() throws {
        let context = try makeContext()
        let open = TaskItem(title: "Open")
        let done = TaskItem(title: "Done", done: true)
        context.insert(open)
        context.insert(done)
        try context.save()

        let removed = TaskActions.clearCompleted(in: context)

        XCTAssertEqual(removed.count, 1)
        XCTAssertEqual(context.allTasks().map(\.title), ["Open"])
    }

    func testClearCompletedWithNoneDoneRemovesNothing() throws {
        let context = try makeContext()
        context.insert(TaskItem(title: "Open"))
        try context.save()

        let removed = TaskActions.clearCompleted(in: context)

        XCTAssertEqual(removed.count, 0)
        XCTAssertEqual(context.allTasks().count, 1)
    }

    func testClearAllEmptiesTheStore() throws {
        let context = try makeContext()
        context.insert(TaskItem(title: "A"))
        context.insert(TaskItem(title: "B", done: true))
        try context.save()

        let removed = TaskActions.clearAll(in: context)

        XCTAssertEqual(removed.count, 2)
        XCTAssertTrue(context.allTasks().isEmpty)
    }

    func testClearAllOnEmptyStoreReturnsZero() throws {
        let context = try makeContext()

        let removed = TaskActions.clearAll(in: context)

        XCTAssertEqual(removed.count, 0)
    }

    func testDeleteRemovesOnlyGivenTasksAndReturnsSnapshots() throws {
        let context = try makeContext()
        let a = TaskItem(title: "A", sortOrder: 0)
        let b = TaskItem(title: "B", sortOrder: 1)
        let c = TaskItem(title: "C", sortOrder: 2)
        [a, b, c].forEach(context.insert)
        try context.save()

        let snaps = TaskActions.delete([a, c], in: context)

        XCTAssertEqual(snaps.map(\.title), ["A", "C"])
        XCTAssertEqual(snaps.map(\.id), [a.id, c.id])
        XCTAssertEqual(context.allTasks().map(\.title), ["B"])
    }

    func testDeleteThenRestoreRoundTripsIdentityAndOrder() throws {
        let context = try makeContext()
        let a = TaskItem(title: "A", done: true,
                         completedAt: Date(timeIntervalSince1970: 42), sortOrder: 3)
        context.insert(a)
        try context.save()

        let snaps = TaskActions.delete([a], in: context)
        XCTAssertTrue(context.allTasks().isEmpty)

        TaskActions.restore(snaps, in: context)

        let restored = context.allTasks().first
        XCTAssertEqual(restored?.id, a.id)
        XCTAssertEqual(restored?.done, true)
        XCTAssertEqual(restored?.completedAt, Date(timeIntervalSince1970: 42))
        XCTAssertEqual(restored?.sortOrder, 3)
    }

    func testClearCompletedReturnsSnapshotsOfRemovedTasks() throws {
        let context = try makeContext()
        let open = TaskItem(title: "Open")
        let done = TaskItem(title: "Done", done: true,
                            completedAt: Date(timeIntervalSince1970: 50), sortOrder: 2)
        context.insert(open)
        context.insert(done)
        try context.save()

        let snaps = TaskActions.clearCompleted(in: context)

        XCTAssertEqual(snaps.map(\.title), ["Done"])
        XCTAssertEqual(snaps.first?.id, done.id)
        XCTAssertEqual(snaps.first?.sortOrder, 2)
        XCTAssertEqual(snaps.first?.completedAt, Date(timeIntervalSince1970: 50))
    }

    func testRestoreReinsertsTasksWithIdentityOrderAndDoneState() throws {
        let context = try makeContext()
        let a = TaskItem(title: "A", sortOrder: 0)
        let b = TaskItem(title: "B", done: true,
                         completedAt: Date(timeIntervalSince1970: 99), sortOrder: 1)
        context.insert(a)
        context.insert(b)
        try context.save()
        let originalOrder = TaskOrdering.ordered(context.allTasks()).map(\.id)

        let snaps = TaskActions.clearAll(in: context)
        XCTAssertTrue(context.allTasks().isEmpty)

        TaskActions.restore(snaps, in: context)

        XCTAssertEqual(context.allTasks().count, 2)
        let byId = Dictionary(uniqueKeysWithValues: context.allTasks().map { ($0.id, $0) })
        XCTAssertEqual(byId[b.id]?.done, true)
        XCTAssertEqual(byId[b.id]?.completedAt, Date(timeIntervalSince1970: 99))
        XCTAssertEqual(byId[b.id]?.sortOrder, 1)
        XCTAssertEqual(TaskOrdering.ordered(context.allTasks()).map(\.id), originalOrder)
    }

    // MARK: - blank-draft exclusion (visible count)

    func testIsBlankDetectsEmptyAndWhitespaceOnlyTitles() {
        XCTAssertTrue(TaskItem(title: "").isBlank)
        XCTAssertTrue(TaskItem(title: "   \n\t").isBlank)
        XCTAssertFalse(TaskItem(title: "buy milk").isBlank)
    }

    func testOrderedTasksExcludesBlankDrafts() throws {
        let context = try makeContext()
        context.insert(TaskItem(title: "Real"))
        context.insert(TaskItem(title: ""))      // empty draft
        context.insert(TaskItem(title: "   "))   // whitespace-only draft
        try context.save()

        // The count source behind the "Delete all N tasks?" dialog and the Siri
        // Clear-All confirmation: only the visible task should be counted.
        XCTAssertEqual(context.orderedTasks().map(\.title), ["Real"])
    }

    // MARK: - add

    func testAddInsertsTaskWithTrimmedTitle() throws {
        let context = try makeContext()

        let item = TaskActions.add(title: "  buy milk  ", in: context)

        XCTAssertEqual(item.title, "buy milk")
        XCTAssertEqual(context.allTasks().map(\.title), ["buy milk"])
    }

    func testAddOnEmptyStoreGetsSortOrderZero() throws {
        let context = try makeContext()

        let item = TaskActions.add(title: "first", in: context)

        XCTAssertEqual(item.sortOrder, 0)
    }

    func testAddAppendsAfterHighestSortOrder() throws {
        let context = try makeContext()
        context.insert(TaskItem(title: "a", sortOrder: 0))
        context.insert(TaskItem(title: "b", sortOrder: 5))
        try context.save()

        let item = TaskActions.add(title: "c", in: context)

        XCTAssertEqual(item.sortOrder, 6)
    }

    func testAddCountsCompletedTasksWhenComputingSortOrder() throws {
        let context = try makeContext()
        // A completed task keeps its sortOrder; a new task must still land after it.
        context.insert(TaskItem(title: "done", done: true, sortOrder: 3))
        try context.save()

        let item = TaskActions.add(title: "new", in: context)

        XCTAssertEqual(item.sortOrder, 4)
    }

    // MARK: - complete

    func testCompleteMarksOpenTaskDone() throws {
        let context = try makeContext()
        let task = TaskItem(title: "open")
        context.insert(task)
        try context.save()

        let completed = TaskActions.complete(id: task.id, in: context)

        XCTAssertEqual(completed?.id, task.id)
        XCTAssertTrue(task.done)
        XCTAssertNotNil(task.completedAt)
    }

    func testCompleteUnknownIDReturnsNil() throws {
        let context = try makeContext()

        let completed = TaskActions.complete(id: UUID(), in: context)

        XCTAssertNil(completed)
    }

    func testCompleteAlreadyDoneTaskDoesNotReopenIt() throws {
        let context = try makeContext()
        let stamp = Date(timeIntervalSince1970: 1000)
        let task = TaskItem(title: "done", done: true, completedAt: stamp)
        context.insert(task)
        try context.save()

        _ = TaskActions.complete(id: task.id, in: context)

        // Guard against toggleDone() flipping a completed task back to open.
        XCTAssertTrue(task.done)
        XCTAssertEqual(task.completedAt, stamp)
    }
}
