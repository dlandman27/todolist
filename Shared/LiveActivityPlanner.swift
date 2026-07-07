import Foundation

/// What `refresh()` should do with the Live Activity, decided purely from snapshots.
enum LiveActivityAction: Equatable {
    case start    // no usable activity — request a fresh one
    case update   // a young live activity exists — just push new content
    case restart  // live but aging/unknown — end it and request fresh to reset the 8h clock
    case none     // user opt-out or system-disabled
}

/// The testable essence of an `Activity`: is it actually presentable, and when did we request it?
struct ActivitySnapshot {
    var isLive: Bool      // activityState is .active or .stale
    var startedAt: Date?  // recorded at request time; nil if unknown
}

enum LiveActivityPlanner {
    /// Live activities older than this are restarted on the next refresh so the
    /// system's 8-hour kill clock resets while the user is still around.
    static let maxAge: TimeInterval = 60 * 60

    /// iOS ends every Live Activity this long after it was requested.
    static let systemLifetime: TimeInterval = 8 * 60 * 60

    static func action(
        userEnabled: Bool,
        systemEnabled: Bool,
        activities: [ActivitySnapshot],
        now: Date,
        maxAge: TimeInterval = LiveActivityPlanner.maxAge
    ) -> LiveActivityAction {
        guard userEnabled, systemEnabled else { return .none }
        guard let live = activities.first(where: { $0.isLive }) else { return .start }
        guard let startedAt = live.startedAt else { return .restart }
        return now.timeIntervalSince(startedAt) >= maxAge ? .restart : .update
    }
}
