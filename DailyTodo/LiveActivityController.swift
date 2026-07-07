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

    /// The end-then-request dance is async; without this guard, back-to-back refreshes
    /// (e.g. onAppear + scenePhase at launch) both see "no live activity" and double-request.
    private var isRequesting = false

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

    /// Start, update, or restart the activity so it reflects the current list —
    /// and so the system's 8-hour kill clock keeps getting reset while the user is active.
    func refresh() {
        guard !TaskStore.isUITesting else { return }

        let storedStart = defaults?.object(forKey: LiveActivityBridge.startedAtKey) as? Date
        let snapshots = Activity<TodoActivityAttributes>.activities.map {
            ActivitySnapshot(isLive: Self.isLive($0.activityState), startedAt: storedStart)
        }

        switch LiveActivityPlanner.action(
            userEnabled: isEnabled,
            systemEnabled: systemEnabled,
            activities: snapshots,
            now: Date()
        ) {
        case .none:
            syncRunningState()
        case .update:
            let content = ActivityContent(
                state: LiveActivityBridge.contentState(),
                staleDate: LiveActivityBridge.staleDate()
            )
            if let live = Activity<TodoActivityAttributes>.activities
                .first(where: { Self.isLive($0.activityState) }) {
                Task { await live.update(content) }
            }
            isRunning = true
        case .start, .restart:
            requestFresh()
        }
    }

    /// Pin the list to the lock screen.
    func start() {
        isEnabled = true
        refresh()
    }

    /// Remove the list from the lock screen and remember the opt-out.
    func stop() {
        isEnabled = false
        defaults?.removeObject(forKey: LiveActivityBridge.startedAtKey)
        for activity in Activity<TodoActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        isRunning = false
    }

    func toggle() {
        // Re-derive from reality first: the OS may have ended the activity (time limit,
        // user dismissal) without the app knowing, leaving `isRunning` stale. Without
        // this, the first tap after a silent end takes the wrong branch and looks dead.
        syncRunningState()
        isRunning ? stop() : start()
    }

    /// End everything (live or zombie) and request a fresh activity, resetting the 8h clock.
    private func requestFresh() {
        guard !isRequesting else { return }
        isRequesting = true
        let existing = Activity<TodoActivityAttributes>.activities
        let startedAt = Date()
        defaults?.set(startedAt, forKey: LiveActivityBridge.startedAtKey)
        let content = ActivityContent(
            state: LiveActivityBridge.contentState(),
            staleDate: startedAt.addingTimeInterval(LiveActivityPlanner.systemLifetime)
        )
        Task {
            defer { isRequesting = false }
            for activity in existing {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            do {
                _ = try Activity.request(
                    attributes: TodoActivityAttributes(),
                    content: content,
                    pushType: nil
                )
                isRunning = true
            } catch {
                print("Live Activity start failed: \(error)")
                isRunning = false
            }
        }
    }

    private static func isLive(_ state: ActivityState) -> Bool {
        state == .active || state == .stale
    }

    private func syncRunningState() {
        isRunning = Activity<TodoActivityAttributes>.activities
            .contains { Self.isLive($0.activityState) }
    }
}
