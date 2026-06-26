import Foundation
import SwiftData

/// A single to-do in the one and only list. No dates, no buckets — just an item.
@Model
final class TaskItem {
    var id: UUID = UUID()
    var title: String = ""
    var done: Bool = false
    /// Creation timestamp, used as a stable tiebreaker for ordering.
    var createdAt: Date = Date()
    /// When the task was last checked off; nil while it's still open.
    var completedAt: Date?
    /// User-assigned priority within the open group; lower sorts first. Untouched
    /// by completion, so a re-opened task returns to its original spot. Defaults to
    /// 0 so existing tasks migrate in place and fall back to `createdAt` order until
    /// the user first reorders.
    var sortOrder: Int = 0
    /// Whether the task is tucked into the stash (hidden from Today/widget/Live Activity).
    var isStashed: Bool = false
    /// When a stashed task auto-returns to Today (local midnight). `nil` while stashed
    /// means "Never" — it returns only when manually pulled back. Ignored when not stashed.
    var stashReturnDate: Date? = nil

    init(
        id: UUID = UUID(),
        title: String,
        done: Bool = false,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        sortOrder: Int = 0,
        isStashed: Bool = false,
        stashReturnDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.done = done
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.sortOrder = sortOrder
        self.isStashed = isStashed
        self.stashReturnDate = stashReturnDate
    }

    /// An in-progress, untitled draft (the app inserts an empty row to type into).
    /// These are app-only editing state and shouldn't surface on the widget / Live Activity.
    var isBlank: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Flip done state and keep `completedAt` in sync.
    func toggleDone() {
        done.toggle()
        completedAt = done ? Date() : nil
    }
}
