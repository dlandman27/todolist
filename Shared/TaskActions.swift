import SwiftData

/// Bulk deletion operations on the list, shared between the manual clear menu and
/// the upcoming midnight auto-delete. Pure data mutation — callers are responsible
/// for any Live Activity / widget refresh afterward.
enum TaskActions {
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
