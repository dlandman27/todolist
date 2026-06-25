import Foundation
import SwiftData

/// A snapshot of a task's restorable state, captured before a bulk delete so the
/// action can be undone. Holds plain values (no SwiftData identity) so it outlives
/// the deleted object.
struct TaskSnapshot {
    let id: UUID
    let title: String
    let done: Bool
    let createdAt: Date
    let completedAt: Date?
    let sortOrder: Int
    let isStashed: Bool
    let stashReturnDate: Date?

    init(_ task: TaskItem) {
        id = task.id
        title = task.title
        done = task.done
        createdAt = task.createdAt
        completedAt = task.completedAt
        sortOrder = task.sortOrder
        isStashed = task.isStashed
        stashReturnDate = task.stashReturnDate
    }
}

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

    /// Delete the given tasks. Returns snapshots of what was removed (for undo).
    /// The single delete primitive every removal path routes through.
    @discardableResult
    static func delete(_ tasks: [TaskItem], in context: ModelContext) -> [TaskSnapshot] {
        let snapshots = tasks.map(TaskSnapshot.init)
        for task in tasks { context.delete(task) }
        try? context.save()
        return snapshots
    }

    /// Delete all completed tasks. Returns snapshots of what was removed (for undo).
    @discardableResult
    static func clearCompleted(in context: ModelContext) -> [TaskSnapshot] {
        delete(context.allTasks().filter { $0.done }, in: context)
    }

    /// Delete every task in Today (open + completed). Stashed tasks are protected —
    /// "Clear All" affects only what's visible, not the stash drawer.
    @discardableResult
    static func clearAll(in context: ModelContext) -> [TaskSnapshot] {
        delete(context.allTasks().filter { !$0.isStashed }, in: context)
    }

    /// Re-insert tasks captured by `clearCompleted`/`clearAll`, preserving their original
    /// id, order, and completion state so the list returns exactly as it was.
    static func restore(_ snapshots: [TaskSnapshot], in context: ModelContext) {
        let existing = Set(context.allTasks().map(\.id))
        for snap in snapshots where !existing.contains(snap.id) {
            context.insert(
                TaskItem(
                    id: snap.id,
                    title: snap.title,
                    done: snap.done,
                    createdAt: snap.createdAt,
                    completedAt: snap.completedAt,
                    sortOrder: snap.sortOrder,
                    isStashed: snap.isStashed,
                    stashReturnDate: snap.stashReturnDate
                )
            )
        }
        try? context.save()
    }

    /// Tuck an open task into the stash with an optional auto-return date (nil = Never).
    static func stash(_ task: TaskItem, until returnDate: Date?, in context: ModelContext) {
        task.isStashed = true
        task.stashReturnDate = returnDate
        try? context.save()
    }

    /// Pull a task out of the stash and drop it at the bottom of the open group.
    static func unstash(_ task: TaskItem, in context: ModelContext) {
        let maxOpenOrder = context.allTasks()
            .filter { !$0.done && !$0.isStashed }
            .map(\.sortOrder)
            .max() ?? -1
        task.isStashed = false
        task.stashReturnDate = nil
        task.sortOrder = maxOpenOrder + 1
        try? context.save()
    }

    /// Delete every stashed task. Returns snapshots of what was removed (for undo).
    @discardableResult
    static func clearStash(in context: ModelContext) -> [TaskSnapshot] {
        delete(context.allTasks().filter { $0.isStashed }, in: context)
    }
}
