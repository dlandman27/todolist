import WidgetKit
import SwiftUI
import AppIntents
import SwiftData

/// Brings 1List to the foreground (default screen — the list) from a control,
/// without a deep link. Used by the Tasks Left control.
@available(iOS 18.0, *)
struct OpenAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Open 1List"
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult { .result() }
}

// MARK: - Quick Add

/// Tap to open the app straight into new-task entry (reuses `dailytodo://add`).
@available(iOS 18.0, *)
struct QuickAddControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlKind.quickAdd) {
            ControlWidgetButton(action: OpenURLIntent(DeepLink.addURL)) {
                Label("Add Task", systemImage: "plus.circle")
            }
        }
        .displayName("Add Task")
    }
}

// MARK: - Tasks Left

/// Shows the open-task count; tap opens the app to the list.
@available(iOS 18.0, *)
struct TasksLeftControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlKind.tasksLeft, provider: Provider()) { count in
            ControlWidgetButton(action: OpenAppIntent()) {
                // One label — the system shortens it for the small slot and shows it
                // in full when the control is sized larger. Lead with the count so the
                // number survives truncation.
                Label(count == 1 ? "1 task left" : "\(count) tasks left", systemImage: "checklist")
            }
        }
        .displayName("Tasks Left")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Int { 3 }
        func currentValue() async throws -> Int {
            ControlCounts.open(in: ModelContext(TaskStore.shared))
        }
    }
}

// MARK: - Stashed

/// Shows the stashed-task count; tap opens the stash drawer (`dailytodo://stash`).
@available(iOS 18.0, *)
struct StashedControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlKind.stashed, provider: Provider()) { count in
            ControlWidgetButton(action: OpenURLIntent(DeepLink.stashURL)) {
                Label("\(count) stashed", systemImage: "archivebox")
            }
        }
        .displayName("Stashed")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Int { 2 }
        func currentValue() async throws -> Int {
            ControlCounts.stashed(in: ModelContext(TaskStore.shared))
        }
    }
}
