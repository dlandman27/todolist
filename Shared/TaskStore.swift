import Foundation
import SwiftData

/// Shared SwiftData container, placed in the App Group container so the app and the
/// widget extension read and write the same store.
///
/// Persistence sits behind this single entry point so the backing engine could be
/// swapped (e.g. for a Codable JSON file in the same App Group) without touching callers.
enum TaskStore {
    static let shared: ModelContainer = makeContainer()

    static func makeContainer() -> ModelContainer {
        let schema = Schema([TaskItem.self])
        let config = ModelConfiguration(
            schema: schema,
            groupContainer: .identifier(AppGroup.identifier)
        )
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
}
