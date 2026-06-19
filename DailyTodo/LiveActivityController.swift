import ActivityKit
import SwiftData
import Foundation
import Observation

/// Owns the lifecycle of the list's Live Activity from the app side: start, keep updated, stop.
/// The user can opt out; the choice persists in the App Group defaults.
@MainActor
@Observable
final class LiveActivityController {
    static let shared = LiveActivityController()

    private let defaults = UserDefaults(suiteName: AppGroup.identifier)
    private let enabledKey = "liveActivityEnabled"

    private(set) var isRunning = false

    private init() {
        syncRunningState()
    }

    /// Whether the user wants the list pinned to the lock screen. Defaults to on.
    var isEnabled: Bool {
        get { defaults?.object(forKey: enabledKey) as? Bool ?? true }
        set { defaults?.set(newValue, forKey: enabledKey) }
    }

    /// Whether Live Activities are permitted by the system (Settings → toggle).
    var systemEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Start the activity if needed, or update the running one to reflect the current list.
    func refresh() {
        syncRunningState()
        guard ActivityAuthorizationInfo().areActivitiesEnabled, isEnabled else { return }

        let state = LiveActivityBridge.contentState()

        if let activity = Activity<TodoActivityAttributes>.activities.first {
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
        } else {
            do {
                _ = try Activity.request(
                    attributes: TodoActivityAttributes(),
                    content: ActivityContent(state: state, staleDate: nil),
                    pushType: nil
                )
            } catch {
                print("Live Activity start failed: \(error)")
            }
        }
        isRunning = true
    }

    /// Pin the list to the lock screen.
    func start() {
        isEnabled = true
        refresh()
    }

    /// Remove the list from the lock screen and remember the opt-out.
    func stop() {
        isEnabled = false
        for activity in Activity<TodoActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        isRunning = false
    }

    func toggle() {
        isRunning ? stop() : start()
    }

    private func syncRunningState() {
        isRunning = !Activity<TodoActivityAttributes>.activities.isEmpty
    }
}
