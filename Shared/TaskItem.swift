import Foundation
import SwiftData

/// A single to-do in the one and only list. No dates, no buckets — just an item.
@Model
final class TaskItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var done: Bool
    /// Sort order within the list, oldest first.
    var createdAt: Date
    /// When the task was last checked off; nil while it's still open.
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        done: Bool = false,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.done = done
        self.createdAt = createdAt
        self.completedAt = completedAt
    }

    /// Flip done state and keep `completedAt` in sync.
    func toggleDone() {
        done.toggle()
        completedAt = done ? Date() : nil
    }
}
