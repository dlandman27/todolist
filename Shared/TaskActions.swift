import Foundation
import SwiftData

/// Data mutations on the list, shared between the app UI, the widget/Live Activity
/// intents, and the Siri App Intents. Pure data mutation — callers are responsible
/// for any Live Activity / widget refresh afterward.
enum TaskActions {
    /// Insert a new task at the bottom of the open group. The title is trimmed, and
    /// `sortOrder` is one past the current maximum (matching the app's inline add) so
    /// the row lands last. Returns the inserted task.
    @discardableResult
    static func add(title: String, in context: ModelContext) -> TaskItem {
        let nextOrder = (context.allTasks().map(\.sortOrder).max() ?? -1) + 1
        let item = TaskItem(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            sortOrder: nextOrder
        )
        context.insert(item)
        try? context.save()
        return item
    }

    /// Mark the task with `id` done. No-op (but still returns the task) if it's already
    /// completed — guarding against `toggleDone()` flipping a done task back to open.
    /// Returns the task, or nil if no task with that id exists.
    @discardableResult
    static func complete(id: UUID, in context: ModelContext) -> TaskItem? {
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })
        guard let task = try? context.fetch(descriptor).first else { return nil }
        if !task.done {
            task.toggleDone()
            try? context.save()
        }
        return task
    }

    /// Delete all completed tasks. Returns the number removed.
    @discardableResult
    static func clearCompleted(in context: ModelContext) -> Int {
        let completed = context.allTasks().filter { $0.done }
        for task in completed { context.delete(task) }
        try? context.save()
        return completed.count
    }

    /// Delete every task. Returns the number removed.
    @discardableResult
    static func clearAll(in context: ModelContext) -> Int {
        let all = context.allTasks()
        for task in all { context.delete(task) }
        try? context.save()
        return all.count
    }
}
