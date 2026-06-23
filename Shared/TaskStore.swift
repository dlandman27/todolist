import Foundation
import SwiftData

/// Shared SwiftData container, placed in the App Group container so the app and the
/// widget extension read and write the same store.
///
/// Persistence sits behind this single entry point so the backing engine could be
/// swapped (e.g. for a Codable JSON file in the same App Group) without touching callers.
enum TaskStore {
    static let shared: ModelContainer = makeContainer()

    /// UI tests launch with this flag to get a clean, isolated store each run.
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitests")
    }

    static func makeContainer() -> ModelContainer {
        let schema = Schema([TaskItem.self])
        let config: ModelConfiguration = isUITesting
            ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            : ModelConfiguration(schema: schema, groupContainer: .identifier(AppGroup.identifier))
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create shared ModelContainer: \(error)")
        }
    }
}

extension ModelContext {
    /// The whole list, oldest first.
    func allTasks() -> [TaskItem] {
        let descriptor = FetchDescriptor<TaskItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return (try? fetch(descriptor)) ?? []
    }

    /// The list in display order — open first, completed sunk to the bottom — for
    /// surfaces that read from the store (widget, Live Activity). Blank drafts (the
    /// app's in-progress empty rows) are excluded so they never show up there. The app
    /// itself drives its `@Query` directly so it can still show the row being typed in.
    func orderedTasks() -> [TaskItem] {
        TaskOrdering.ordered(allTasks().filter { !$0.isBlank })
    }
}
