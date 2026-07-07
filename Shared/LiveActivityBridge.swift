import ActivityKit
import SwiftData
import Foundation

/// Updates already-running Live Activities with fresh task data. Safe to call from either the
/// app or the widget extension (e.g. from an App Intent). Does NOT start a new activity —
/// starting requires the app to be in the foreground and lives in `LiveActivityController`.
enum LiveActivityBridge {
    /// When the current activity was requested, persisted in the App Group so both
    /// the app (which starts activities) and the extension (which updates them) agree.
    static let startedAtKey = "liveActivityStartedAt"

    /// The moment the system will kill the current activity — content is stale from then on.
    static func staleDate() -> Date? {
        guard let startedAt = UserDefaults(suiteName: AppGroup.identifier)?
            .object(forKey: startedAtKey) as? Date else { return nil }
        return startedAt.addingTimeInterval(LiveActivityPlanner.systemLifetime)
    }

    static func contentState() -> TodoActivityAttributes.ContentState {
        let context = ModelContext(TaskStore.shared)
        // orderedTasks() = display order with blank drafts excluded, matching the widget.
        let tasks = context.orderedTasks().map {
            LiveTask(id: $0.id, title: $0.title, done: $0.done)
        }
        return TodoActivityAttributes.ContentState(tasks: tasks)
    }

    static func updateRunningActivities() async {
        let state = contentState()
        for activity in Activity<TodoActivityAttributes>.activities {
            await activity.update(ActivityContent(state: state, staleDate: staleDate()))
        }
    }
}
