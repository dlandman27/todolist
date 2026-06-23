import ActivityKit
import SwiftData
import Foundation

/// Updates already-running Live Activities with fresh task data. Safe to call from either the
/// app or the widget extension (e.g. from an App Intent). Does NOT start a new activity —
/// starting requires the app to be in the foreground and lives in `LiveActivityController`.
enum LiveActivityBridge {
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
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }
}
