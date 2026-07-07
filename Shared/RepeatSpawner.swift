import Foundation
import SwiftData
import WidgetKit

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
        startDate: Date? = nil,
        now: Date,
        hasOpenInstance: Bool,
        calendar: Calendar = .current
    ) -> Bool {
        if hasOpenInstance { return false }
        let today = calendar.startOfDay(for: now)

        // Not yet begun: a future start date silences the rule entirely.
        if let start = startDate, calendar.startOfDay(for: start) > today {
            return false
        }

        if let last = lastSpawnedDay, calendar.startOfDay(for: last) >= today {
            return false   // already spawned today (or marker is in the future)
        }

        let lookbackFloor = calendar.date(byAdding: .day, value: -catchUpLookbackDays, to: today)!
        var lower: Date
        if let last = lastSpawnedDay {
            lower = max(calendar.startOfDay(for: last), lookbackFloor)
        } else {
            lower = calendar.date(byAdding: .day, value: -1, to: today)!   // only today
        }
        // Scheduled days before the start date never count toward catch-up.
        if let start = startDate {
            let dayBeforeStart = calendar.date(byAdding: .day, value: -1,
                                               to: calendar.startOfDay(for: start))!
            lower = max(lower, dayBeforeStart)
        }

        // Any scheduled day in (lower, today]?
        var dayCursor = calendar.date(byAdding: .day, value: 1, to: lower)!
        while dayCursor <= today {
            if cadence.isScheduled(on: dayCursor, calendar: calendar) { return true }
            dayCursor = calendar.date(byAdding: .day, value: 1, to: dayCursor)!
        }
        return false
    }

    /// A rule with an end date runs through that day (inclusive) and is expired —
    /// and deleted by `runIfNeeded` — once a later day starts. Pure and testable.
    static func isExpired(endDate: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let endDate else { return false }
        return calendar.startOfDay(for: now) > calendar.startOfDay(for: endDate)
    }

    /// For each rule, spawn a task if it's due (see `shouldSpawn`) and advance its
    /// marker; rules past their end date are deleted instead (already-spawned tasks
    /// are independent and stay). Called from the app's daily catch-up alongside
    /// `DailyCleanup` / `StashReturn`.
    static func runIfNeeded(in context: ModelContext, now: Date = Date(), calendar: Calendar = .current) {
        var changed = false
        for rule in context.repeatRules() {
            if isExpired(endDate: rule.endDate, now: now, calendar: calendar) {
                context.delete(rule)
                changed = true
                continue
            }
            guard let cadence = rule.cadence else { continue }
            let hasOpen = context.hasOpenInstance(ofRule: rule.id)
            if shouldSpawn(cadence: cadence, lastSpawnedDay: rule.lastSpawnedDay,
                           startDate: rule.startDate,
                           now: now, hasOpenInstance: hasOpen, calendar: calendar) {
                TaskActions.add(title: rule.name, notes: rule.notes, repeatRuleID: rule.id, in: context)
                rule.lastSpawnedDay = calendar.startOfDay(for: now)
                changed = true
            }
        }
        if changed {
            try? context.save()
            Surfaces.reload()
        }
    }
}
