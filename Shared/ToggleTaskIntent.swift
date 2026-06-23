import AppIntents
import SwiftData
import WidgetKit

/// Flips a task's done state from a widget (or Live Activity) without launching the app.
/// Conforms to `LiveActivityIntent` (which refines `AppIntent`) so a tap on the Live
/// Activity runs in-process and can update the running activity — a plain `AppIntent`
/// doesn't reliably refresh the Lock Screen. Still works in home-screen widgets too.
struct ToggleTaskIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Toggle Task"
    static var isDiscoverable = false

    @Parameter(title: "Task ID")
    var taskID: String

    init() {}

    init(taskID: UUID) {
        self.taskID = taskID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let uuid = UUID(uuidString: taskID) else { return .result() }

        let context = ModelContext(TaskStore.shared)
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.id == uuid }
        )
        if let task = try context.fetch(descriptor).first {
            task.toggleDone()
            try context.save()
        }

        await LiveActivityBridge.updateRunningActivities()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
