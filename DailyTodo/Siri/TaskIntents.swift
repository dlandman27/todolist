import AppIntents
import SwiftData
import WidgetKit

/// Refresh the Lock Screen Live Activity and home-screen widgets after a mutation,
/// mirroring what `ToggleTaskIntent` does. Shared by every mutating intent below.
private func refreshSurfaces() async {
    await LiveActivityBridge.updateRunningActivities()
    WidgetCenter.shared.reloadAllTimelines()
}

/// Add a new to-do. By voice, Siri prompts for the title; in the Shortcuts app the
/// title is passed directly as an action input.
struct AddTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Task"
    static var description = IntentDescription("Add a new to-do to your list.")

    @Parameter(title: "Task", requestValueDialog: "What would you like to add?")
    var taskTitle: String

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$taskTitle) to 1List")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<TaskEntity> & ProvidesDialog {
        let context = ModelContext(TaskStore.shared)
        let item = TaskActions.add(title: taskTitle, in: context)
        await refreshSurfaces()
        return .result(
            value: TaskEntity(id: item.id, title: item.title),
            dialog: "Added \(item.title)."
        )
    }
}

/// Check off an existing open task. Siri presents the open-tasks pick-list (via
/// `TaskEntityQuery.suggestedEntities`) for disambiguation.
struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Task"
    static var description = IntentDescription("Mark a task on your list as done.")

    @Parameter(title: "Task")
    var task: TaskEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Complete \(\.$task) in 1List")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(TaskStore.shared)
        guard TaskActions.complete(id: task.id, in: context) != nil else {
            return .result(dialog: "I couldn't find that task.")
        }
        await refreshSurfaces()
        return .result(dialog: "Completed \(task.title).")
    }
}

/// Ask what's left. Speaks the open tasks back and returns them for composability.
struct OpenTasksIntent: AppIntent {
    static var title: LocalizedStringResource = "What's Left"
    static var description = IntentDescription("Ask what's still on your list.")

    static var parameterSummary: some ParameterSummary {
        Summary("Get what's left on 1List")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[TaskEntity]> & ProvidesDialog {
        let context = ModelContext(TaskStore.shared)
        let open = context.orderedTasks().filter { !$0.done }
        let entities = open.map { TaskEntity(id: $0.id, title: $0.title) }

        let dialog: IntentDialog
        if open.isEmpty {
            dialog = "Your list is empty."
        } else {
            let noun = open.count == 1 ? "task" : "tasks"
            let titles = open.map(\.title).joined(separator: ", ")
            dialog = IntentDialog("You have \(open.count) \(noun): \(titles)")
        }
        return .result(value: entities, dialog: dialog)
    }
}

/// Remove all completed tasks.
struct ClearCompletedIntent: AppIntent {
    static var title: LocalizedStringResource = "Clear Completed"
    static var description = IntentDescription("Remove all completed tasks from your list.")

    static var parameterSummary: some ParameterSummary {
        Summary("Clear completed tasks from 1List")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(TaskStore.shared)
        let removed = TaskActions.clearCompleted(in: context)
        await refreshSurfaces()
        let dialog: IntentDialog = removed == 0
            ? "No completed tasks to clear."
            : "Cleared \(removed) completed \(removed == 1 ? "task" : "tasks")."
        return .result(dialog: dialog)
    }
}

/// Delete every task — confirms first, since it's destructive and irreversible.
struct ClearAllIntent: AppIntent {
    static var title: LocalizedStringResource = "Clear All Tasks"
    static var description = IntentDescription("Delete every task on your list.")

    static var parameterSummary: some ParameterSummary {
        Summary("Clear all tasks from 1List")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(TaskStore.shared)
        let count = context.allTasks().count
        guard count > 0 else {
            return .result(dialog: "Your list is already empty.")
        }
        try await requestConfirmation(
            result: .result(dialog: "Delete all \(count) \(count == 1 ? "task" : "tasks")?")
        )
        TaskActions.clearAll(in: context)
        await refreshSurfaces()
        return .result(dialog: "Cleared your list.")
    }
}
