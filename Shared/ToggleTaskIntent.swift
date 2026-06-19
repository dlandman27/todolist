import AppIntents
import SwiftData
import WidgetKit

/// Flips a task's done state from a widget (or Live Activity) without launching the app.
/// Runs in the background via App Intents, updates the Live Activity, and reloads widgets.
struct ToggleTaskIntent: AppIntent {
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
