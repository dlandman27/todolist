import Foundation

/// How the open tasks are ordered, on every surface (app list, widget, Live
/// Activity). Manual is the classic drag-to-arrange order; the others are
/// derived, non-destructive views over the same tasks — switching away and back
/// never touches `sortOrder`. Persisted in the App Group so the widget and
/// Live Activity stay in step with the app.
enum TaskSort: String, CaseIterable, Identifiable {
    case manual
    case newest
    case oldest
    case alphabetical

    static let defaultsKey = "taskSortMode"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual: "Manual"
        case .newest: "Newest First"
        case .oldest: "Oldest First"
        case .alphabetical: "A to Z"
        }
    }

    /// The stored choice, defaulting to manual.
    static var current: TaskSort {
        let raw = AppGroup.defaults?.string(forKey: defaultsKey) ?? ""
        return TaskSort(rawValue: raw) ?? .manual
    }
}
