import Foundation
import SwiftData

/// Counts surfaced by the Control Center controls. Pure wrappers over the store's
/// display helpers so the counting rules stay testable without WidgetKit.
enum ControlCounts {
    /// Open (not done) tasks in Today. Excludes done, stashed, and blank drafts —
    /// `orderedTasks()` already drops the latter two.
    static func open(in context: ModelContext) -> Int {
        context.orderedTasks().filter { !$0.done }.count
    }

    /// Tasks tucked in the stash drawer.
    static func stashed(in context: ModelContext) -> Int {
        context.stashedTasks().count
    }
}
