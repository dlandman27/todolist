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
}
