import XCTest
import SwiftData
@testable import DailyTodo

final class ControlCountsTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: TaskItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    func testOpenCountsOnlyOpenTodayTasks() throws {
        let context = try makeContext()
        context.insert(TaskItem(title: "Open one"))
        context.insert(TaskItem(title: "Open two"))
        context.insert(TaskItem(title: "Done", done: true))
        context.insert(TaskItem(title: "Stashed", isStashed: true))
        context.insert(TaskItem(title: ""))            // blank draft — excluded
        try context.save()

        XCTAssertEqual(ControlCounts.open(in: context), 2)
    }

    func testStashedCountsOnlyStashedTasks() throws {
        let context = try makeContext()
        context.insert(TaskItem(title: "Open"))
        context.insert(TaskItem(title: "Stash one", isStashed: true))
        context.insert(TaskItem(title: "Stash two", isStashed: true))
        try context.save()

        XCTAssertEqual(ControlCounts.stashed(in: context), 2)
    }
}
