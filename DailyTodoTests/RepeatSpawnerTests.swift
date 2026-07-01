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
}
