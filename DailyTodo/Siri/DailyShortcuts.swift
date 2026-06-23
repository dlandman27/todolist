import AppIntents

/// Registers ready-made "Hey Siri" phrases for the list's intents. Each intent also
/// shows up as an action in the Shortcuts app automatically; this provider adds the
/// zero-setup voice phrases on top. Every phrase must contain the app name ("Daily").
struct DailyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Add to \(.applicationName)",
                "Add a task to \(.applicationName)"
            ],
            shortTitle: "Add Task",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: CompleteTaskIntent(),
            phrases: [
                "Complete a task in \(.applicationName)",
                "Check off a task in \(.applicationName)"
            ],
            shortTitle: "Complete Task",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: OpenTasksIntent(),
            phrases: [
                "What's on my \(.applicationName) list",
                "What's left in \(.applicationName)"
            ],
            shortTitle: "What's Left",
            systemImageName: "list.bullet"
        )
        AppShortcut(
            intent: ClearCompletedIntent(),
            phrases: [
                "Clear completed in \(.applicationName)"
            ],
            shortTitle: "Clear Completed",
            systemImageName: "checkmark.circle.badge.xmark"
        )
        AppShortcut(
            intent: ClearAllIntent(),
            phrases: [
                "Clear my \(.applicationName) list"
            ],
            shortTitle: "Clear All",
            systemImageName: "trash"
        )
    }
}
