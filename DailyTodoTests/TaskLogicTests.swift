import XCTest
import SwiftData
@testable import DailyTodo

final class TaskLogicTests: XCTestCase {

    // MARK: - Model

    func testToggleDoneSetsAndClearsCompletedAt() {
        let task = TaskItem(title: "Test")
        XCTAssertFalse(task.done)
        XCTAssertNil(task.completedAt)

        task.toggleDone()
        XCTAssertTrue(task.done)
        XCTAssertNotNil(task.completedAt, "completing a task should stamp completedAt")

        task.toggleDone()
        XCTAssertFalse(task.done)
        XCTAssertNil(task.completedAt, "re-opening a task should clear completedAt")
    }

    // MARK: - Ordering

    func testOpenTasksOrderBySortOrder() {
        let a = TaskItem(title: "A", sortOrder: 2)
        let b = TaskItem(title: "B", sortOrder: 0)
        let c = TaskItem(title: "C", sortOrder: 1)
        // Input order is irrelevant; sortOrder drives it.
        XCTAssertEqual(TaskOrdering.ordered([a, b, c]).map(\.title), ["B", "C", "A"])
    }

    func testEqualSortOrderFallsBackToCreatedAt() {
        // Existing tasks all migrate to sortOrder 0; createdAt keeps them stable.
        let a = TaskItem(title: "A", createdAt: Date(timeIntervalSince1970: 1))
        let b = TaskItem(title: "B", createdAt: Date(timeIntervalSince1970: 2))
        let c = TaskItem(title: "C", createdAt: Date(timeIntervalSince1970: 3))
        XCTAssertEqual(TaskOrdering.ordered([c, a, b]).map(\.title), ["A", "B", "C"])
    }

    func testCompletedTasksSinkByCompletionTime() {
        let a = TaskItem(title: "A", sortOrder: 0)
        let b = TaskItem(title: "B", sortOrder: 1)
        let c = TaskItem(title: "C", sortOrder: 2)
        a.done = true; a.completedAt = Date(timeIntervalSince1970: 100)
        c.done = true; c.completedAt = Date(timeIntervalSince1970: 50)

        // Open task (B) first, then completed ones in check-off order: C@50, A@100.
        XCTAssertEqual(TaskOrdering.ordered([a, b, c]).map(\.title), ["B", "C", "A"])
    }

    func testReopenedTaskReturnsToItsPrioritySpot() {
        let a = TaskItem(title: "A", sortOrder: 0)
        let b = TaskItem(title: "B", sortOrder: 1)
        let c = TaskItem(title: "C", sortOrder: 2)
        // B is completed, then re-opened: sortOrder is untouched, so it lands
        // back between A and C.
        b.done = true; b.completedAt = Date(timeIntervalSince1970: 50)
        XCTAssertEqual(TaskOrdering.ordered([a, b, c]).map(\.title), ["A", "C", "B"])
        b.done = false; b.completedAt = nil
        XCTAssertEqual(TaskOrdering.ordered([a, b, c]).map(\.title), ["A", "B", "C"])
    }

    // MARK: - Reordering

    func testMoveReordersOpenGroup() {
        let a = TaskItem(title: "A", sortOrder: 0)
        let b = TaskItem(title: "B", sortOrder: 1)
        let c = TaskItem(title: "C", sortOrder: 2)
        let ordered = TaskOrdering.ordered([a, b, c])
        // Drag C (index 2) to the top (offset 0).
        let result = TaskOrdering.openOrderAfterMove(ordered, from: [2], to: 0)
        XCTAssertEqual(result.map(\.title), ["C", "A", "B"])
    }

    func testMoveClampsAtCompletedDivider() {
        let a = TaskItem(title: "A", sortOrder: 0)
        let b = TaskItem(title: "B", sortOrder: 1)
        let c = TaskItem(title: "C", sortOrder: 2)
        c.done = true; c.completedAt = Date(timeIntervalSince1970: 50)
        let ordered = TaskOrdering.ordered([a, b, c]) // [A, B, C(done)]
        // Try to drag A (index 0) down past the divider into the completed zone.
        let result = TaskOrdering.openOrderAfterMove(ordered, from: [0], to: 3)
        // A only moves to the bottom of the open group; C is untouched.
        XCTAssertEqual(result.map(\.title), ["B", "A"])
    }

    // MARK: - Store

    func testInsertAndFetchOldestFirst() throws {
        let container = try ModelContainer(
            for: TaskItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        context.insert(TaskItem(title: "Buy milk", createdAt: Date(timeIntervalSince1970: 1)))
        context.insert(TaskItem(title: "Call mom", createdAt: Date(timeIntervalSince1970: 2)))
        try context.save()

        let all = context.allTasks()
        XCTAssertEqual(all.map(\.title), ["Buy milk", "Call mom"])
    }
}
