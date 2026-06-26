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

        if isUITesting {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [config])
        }

        // Production: shared App Group store, mirrored to the user's private iCloud DB.
        let cloudConfig = ModelConfiguration(
            schema: schema,
            groupContainer: .identifier(AppGroup.identifier),
            cloudKitDatabase: .private("iCloud.com.dylanlandman.dailytodo")
        )
        if let container = try? ModelContainer(for: schema, configurations: [cloudConfig]) {
            return container
        }

        // CloudKit unavailable (no iCloud account, missing entitlement, etc.) — keep the
        // app fully usable offline with a local-only store in the same shared container.
        print("CloudKit container unavailable; falling back to local-only store.")
        let localConfig = ModelConfiguration(
            schema: schema,
            groupContainer: .identifier(AppGroup.identifier)
        )
        do {
            return try ModelContainer(for: schema, configurations: [localConfig])
        } catch {
            fatalError("Failed to create local ModelContainer: \(error)")
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

    /// The list in display order for surfaces that read from the store (widget, Live
    /// Activity). Excludes blank drafts AND stashed tasks — neither belongs on a
    /// "today" surface.
    func orderedTasks() -> [TaskItem] {
        TaskOrdering.ordered(allTasks().filter { !$0.isBlank && !$0.isStashed })
    }

    /// Stashed tasks for the stash drawer: soonest auto-return first, "Never" (no
    /// return date) sorted last.
    func stashedTasks() -> [TaskItem] {
        allTasks()
            .filter { $0.isStashed }
            .sorted {
                ($0.stashReturnDate ?? .distantFuture) < ($1.stashReturnDate ?? .distantFuture)
            }
    }
}
