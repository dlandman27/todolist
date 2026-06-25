import Foundation
import SwiftData
import WidgetKit

/// Returns stashed tasks to Today once their local-midnight return date has passed.
/// `due` is the pure, testable core; `runIfNeeded` wires it to the store and reuses
/// `TaskActions.unstash` so a returned task lands at the bottom of the open group.
/// Shares the daily-boundary catch-up model with `DailyCleanup`.
enum StashReturn {
    /// Stashed tasks whose return date is in the past (Never items, with no date, never qualify).
    static func due(_ tasks: [TaskItem], now: Date) -> [TaskItem] {
        tasks.filter { task in
            guard task.isStashed, let date = task.stashReturnDate else { return false }
            return date <= now
        }
    }

    /// Un-stash all due items. Returns the number returned (so the caller can refresh).
    @discardableResult
    static func runIfNeeded(in context: ModelContext, now: Date = Date()) -> Int {
        let due = due(context.stashedTasks(), now: now)
        for task in due {
            TaskActions.unstash(task, in: context)
        }
        if !due.isEmpty {
            WidgetCenter.shared.reloadAllTimelines()
        }
        return due.count
    }
}
