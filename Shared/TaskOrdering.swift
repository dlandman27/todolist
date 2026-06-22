import Foundation

/// How the list is ordered: open tasks first by their manual priority
/// (`sortOrder`, with `createdAt` as a stable tiebreaker), completed ones sunk to
/// the bottom in the order they were checked off. Pure and testable.
enum TaskOrdering {
    static func ordered(_ tasks: [TaskItem]) -> [TaskItem] {
        let open = tasks.filter { !$0.done }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return lhs.createdAt < rhs.createdAt
            }
        let done = tasks.filter { $0.done }
            .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
        return open + done
    }

    /// Apply a drag within the open group. `tasks` is the displayed order (open
    /// first, then completed) and `source`/`destination` come straight from
    /// SwiftUI's `.onMove`. Completed tasks never move, so source indices are
    /// limited to the open range and the destination is clamped at the divider.
    /// Returns the open tasks in their new order — the caller persists this by
    /// writing `sortOrder = index`.
    static func openOrderAfterMove(
        _ tasks: [TaskItem],
        from source: IndexSet,
        to destination: Int
    ) -> [TaskItem] {
        var open = tasks.filter { !$0.done }
        let clampedSource = IndexSet(source.filter { $0 < open.count })
        guard !clampedSource.isEmpty else { return open }
        open.move(fromOffsets: clampedSource, toOffset: min(destination, open.count))
        return open
    }
}
