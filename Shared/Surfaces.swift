import WidgetKit

/// Stable identifiers for the Control Center controls. Shared so the app can ask
/// ControlKit to reload a control by kind without importing the widget extension.
enum ControlKind {
    static let quickAdd = "QuickAddControl"
    static let tasksLeft = "TasksLeftControl"
    static let stashed = "StashedControl"
}

/// Single entry point to refresh every read-only surface after a data mutation:
/// home-screen / Lock Screen widgets, and — on iOS 18+ — Control Center controls.
enum Surfaces {
    static func reload() {
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadControls(ofKind: ControlKind.tasksLeft)
            ControlCenter.shared.reloadControls(ofKind: ControlKind.stashed)
        }
    }
}
