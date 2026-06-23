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

        XCTAssertEqual(removed, 1)
        XCTAssertEqual(context.allTasks().map(\.title), ["Open"])
    }

    func testClearCompletedWithNoneDoneRemovesNothing() throws {
        let context = try makeContext()
        context.insert(TaskItem(title: "Open"))
        try context.save()

        let removed = TaskActions.clearCompleted(in: context)

        XCTAssertEqual(removed, 0)
        XCTAssertEqual(context.allTasks().count, 1)
    }

    func testClearAllEmptiesTheStore() throws {
        let context = try makeContext()
        context.insert(TaskItem(title: "A"))
        context.insert(TaskItem(title: "B", done: true))
        try context.save()

        let removed = TaskActions.clearAll(in: context)

        XCTAssertEqual(removed, 2)
        XCTAssertTrue(context.allTasks().isEmpty)
    }

    func testClearAllOnEmptyStoreReturnsZero() throws {
        let context = try makeContext()

        let removed = TaskActions.clearAll(in: context)

        XCTAssertEqual(removed, 0)
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
