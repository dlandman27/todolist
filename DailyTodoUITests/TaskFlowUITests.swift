import XCTest

final class TaskFlowUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uitests"]   // clean in-memory store, no Live Activity
        app.launch()
    }

    // MARK: - Helpers

    private var taskFields: XCUIElementQuery {
        app.textFields.matching(identifier: "taskField")
    }

    private func field(withValue value: String) -> XCUIElement {
        app.textFields.matching(
            NSPredicate(format: "identifier == %@ AND value == %@", "taskField", value)
        ).firstMatch
    }

    private func dismissKeyboard() {
        app.staticTexts["title"].tap()
    }

    /// Tap the empty area to start a draft, type, and commit by resigning focus.
    @discardableResult
    private func addTask(_ title: String) -> XCUIElement {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "keyboard should appear")
        app.typeText(title)
        dismissKeyboard()
        let committed = field(withValue: title)
        XCTAssertTrue(committed.waitForExistence(timeout: 3), "\(title) should be committed")
        return committed
    }

    // MARK: - Tests

    func testAddTasks() {
        addTask("Buy milk")
        addTask("Call mom")
        XCTAssertEqual(taskFields.count, 2)
    }

    func testCheckingOffSinksToBottom() {
        addTask("First")
        addTask("Second")

        // Check off the top task.
        app.buttons.matching(identifier: "toggle").element(boundBy: 0).tap()

        // Order should become: Second (open), First (done).
        XCTAssertEqual(taskFields.element(boundBy: 0).value as? String, "Second")
        XCTAssertEqual(taskFields.element(boundBy: 1).value as? String, "First")
    }

    func testDeleteTask() {
        let row = addTask("Temp")
        row.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertFalse(field(withValue: "Temp").waitForExistence(timeout: 2))
    }
}
