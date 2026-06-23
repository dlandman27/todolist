import AppIntents
import SwiftData

/// A Siri / Shortcuts-facing representation of a `TaskItem`. Used as the parameter type
/// for the "complete a task" intent (so Siri can present a pick-list) and as the
/// returned value of the "what's left" intent (so it's composable in the Shortcuts app).
struct TaskEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Task"
    static var defaultQuery = TaskEntityQuery()

    let id: UUID
    let title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

/// Resolves `TaskEntity` values from the shared App Group store. `suggestedEntities`
/// returns only open tasks (the disambiguation pick-list for "complete a task").
struct TaskEntityQuery: EntityQuery {
    func entities(for identifiers: [TaskEntity.ID]) async throws -> [TaskEntity] {
        let context = ModelContext(TaskStore.shared)
        return identifiers.compactMap { id in
            let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })
            guard let task = try? context.fetch(descriptor).first else { return nil }
            return TaskEntity(id: task.id, title: task.title)
        }
    }

    func suggestedEntities() async throws -> [TaskEntity] {
        let context = ModelContext(TaskStore.shared)
        return context.orderedTasks()
            .filter { !$0.done }
            .map { TaskEntity(id: $0.id, title: $0.title) }
    }
}
