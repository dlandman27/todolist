import Foundation
import SwiftData

/// Decides when a `RepeatRule` should add a fresh task, and (via `runIfNeeded`) does it
/// during the app's daily catch-up. `shouldSpawn` is the pure, testable core — same
/// pattern as `DailyCleanup.decide` / `StashReturn.due`.
enum RepeatSpawner {

    /// How far back a single catch-up will look for a missed scheduled day, bounding the
    /// day-walk when the app hasn't been opened in a long time.
    private static let catchUpLookbackDays = 45

    /// Whether `rule` should spawn a task now. True only when there's no open instance,
    /// it hasn't already spawned today, and a scheduled day falls in the window since the
    /// last spawn (a brand-new rule only fires when today itself is scheduled).
    static func shouldSpawn(
        cadence: RepeatCadence,
        lastSpawnedDay: Date?,
        now: Date,
        hasOpenInstance: Bool,
        calendar: Calendar = .current
    ) -> Bool {
        if hasOpenInstance { return false }
        let today = calendar.startOfDay(for: now)

        if let last = lastSpawnedDay, calendar.startOfDay(for: last) >= today {
            return false   // already spawned today (or marker is in the future)
        }

        let lookbackFloor = calendar.date(byAdding: .day, value: -catchUpLookbackDays, to: today)!
        let lower: Date
        if let last = lastSpawnedDay {
            lower = max(calendar.startOfDay(for: last), lookbackFloor)
        } else {
            lower = calendar.date(byAdding: .day, value: -1, to: today)!   // only today
        }

        // Any scheduled day in (lower, today]?
        var dayCursor = calendar.date(byAdding: .day, value: 1, to: lower)!
        while dayCursor <= today {
            if cadence.isScheduled(on: dayCursor, calendar: calendar) { return true }
            dayCursor = calendar.date(byAdding: .day, value: 1, to: dayCursor)!
        }
        return false
    }
}
