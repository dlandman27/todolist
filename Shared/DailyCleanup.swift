import Foundation
import SwiftData
import WidgetKit

/// Auto-clears completed tasks at the end of each day. The date logic is the pure,
/// testable `decide`; `runIfNeeded` wires it to the App Group defaults and reuses
/// `TaskActions.clearCompleted` so the automatic purge matches the manual menu action.
///
/// There is no exact-midnight background execution (iOS can't guarantee it). Instead
/// the purge is a catch-up check run on app foreground and by a foreground midnight
/// timer — see the app layer.
enum DailyCleanup {
    /// `@AppStorage` key for the user toggle (default on).
    static let enabledKey = "autoClearEnabled"
    /// Stores the start-of-day the purge last ran, so we fire once per new day.
    static let lastClearedKey = "lastClearedDay"

    /// Whether auto-clear is enabled. Defaults to true when unset.
    static var isEnabled: Bool {
        AppGroup.defaults?.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Pure decision: given the last-cleared day and the current time, should we purge
    /// completed tasks, and what should the stored marker become?
    ///
    /// - First run (no marker): record today, do NOT purge (never nuke tasks made on install).
    /// - New day since last purge + enabled: purge, advance marker to today (also catches missed days).
    /// - Same day, or disabled: no purge; the marker stays put so enabling later triggers one catch-up.
    static func decide(
        lastCleared: Date?,
        now: Date,
        enabled: Bool,
        calendar: Calendar = .current
    ) -> (purge: Bool, newMarker: Date) {
        let today = calendar.startOfDay(for: now)
        guard let last = lastCleared else {
            return (false, today)
        }
        let lastDay = calendar.startOfDay(for: last)
        if enabled && lastDay < today {
            return (true, today)
        }
        return (false, lastDay)
    }

    /// Run a catch-up purge if a new day has started. Returns true if it purged, so the
    /// caller can refresh the Live Activity (widgets are reloaded here).
    @discardableResult
    static func runIfNeeded(in context: ModelContext, now: Date = Date()) -> Bool {
        let defaults = AppGroup.defaults
        let last = defaults?.object(forKey: lastClearedKey) as? Date
        let result = decide(lastCleared: last, now: now, enabled: isEnabled)
        defaults?.set(result.newMarker, forKey: lastClearedKey)
        if result.purge {
            TaskActions.clearCompleted(in: context)
            Surfaces.reload()
        }
        return result.purge
    }
}
