# Repeating Todos (Settings-managed rules) — Design

**Date:** 2026-07-01
**Status:** Approved, ready for implementation plan

> **Supersedes** `2026-07-01-repeating-tasks-design.md`. That earlier design (a
> single task that reschedules itself, daily/every-N-days, an overloaded/split
> stash, long-press editing) was built on the `repeating-tasks` branch and then
> reconsidered. This design replaces it wholesale and is built fresh from `main`;
> the old branch is abandoned, not merged.

## Problem

The app is one dateless list you trust to show what matters today. A few things
recur — "check finances once a month," "water the plants every few days" — and
retyping them is the only friction. We want to remove that friction **without**
turning the app into a task manager. Repeating is a *convenience that re-adds a
task for you*, never a scheduler that tells you what to do.

## Guiding principle

**A repeat is not a special kind of task. It's a small rule that quietly adds an
ordinary task to your list on a rhythm.** Each task it adds is a brand-new,
independent todo — same name as last time, nothing more. Once it's in your list
it is a normal task in every way: check it, edit it, stash it to another day,
delete it — all of which affect only that one task, never the rule. The rule
never nags, never forecasts, never pipelines a backlog. You are always in
control; the rule is just a typist.

Consequences of taking that principle seriously:
- **Low-frequency only.** Weekly and monthly. No daily, no every-N-days — a task
  that reappears every day is exactly the "log your food/workout" treadmill that
  kills the app.
- **No anticipation surface.** No countdown, no "next: Tuesday" in Today, no
  notifications. The task simply appears when its day comes, as if you'd typed
  it. Knowing when the next one lands is *not* the point — offloading that is.
- **Rules live apart from tasks.** Repeating is configured in Settings, not on
  the task and not in the stash. Out in Today, a spawned task carries no badge
  and no special behavior.
- **The stash is untouched.** Stash stays exactly what it is today: one-off tasks
  you pushed to a future date. It knows nothing about repeats.

## Decisions

| Question | Decision |
|----------|----------|
| What is a repeat | A persistent **rule** (name + schedule) that spawns independent one-shot tasks |
| Cadence | **Weekly** (choose weekdays) or **Monthly** (choose day(s) of month). Nothing finer. |
| End date / history | **None.** A rule runs until you delete it; spawned tasks keep no per-task history. (YAGNI; can revisit.) |
| Where rules live | **Settings → "Repeating" section** — a small managed list |
| Create / edit / delete | All in Settings. Editing changes the name/schedule of *future* spawns only. Deleting stops future spawns; already-spawned tasks are left alone. |
| Spawned task | An ordinary `TaskItem` added to the bottom of Today's open group, titled with the rule's name; no badge, no visible link |
| Anti-pileup guard | If an **open** (not-done) task from this rule is still in the list (Today or stash), do **not** add another |
| When it spawns | Quiet catch-up on app open / day-change (same model as `DailyCleanup` / `StashReturn`); no background execution |
| Missed scheduled days | At most **one** catch-up task per rule, not one per missed occurrence |
| Interaction with stash | A spawned task can be stashed like any task; it then just lives in the stash as a normal stashed task |
| Interaction with daily cleanup | Spawned tasks are normal tasks — completed ones auto-clear as usual; the rule spawns a fresh one on its next scheduled day |
| Header / title | **Unchanged.** No new header icon. (A centered-title header restyle was discussed and explicitly deferred as a separate cosmetic project.) |
| Widget / Live Activity | Unchanged — spawned tasks are ordinary tasks and surface normally |

## Design

### Data model

A new SwiftData `@Model`, CloudKit-backed (so every stored property is optional or
defaulted):

```
@Model final class RepeatRule {
    var id: UUID = UUID()
    var name: String = ""            // the title given to spawned tasks
    var cadenceData: String? = nil   // JSON-encoded RepeatCadence (see below)
    var createdAt: Date = Date()
    /// Start-of-day of the last day this rule spawned a task, so it fires at most
    /// once per scheduled day and supports missed-day catch-up. nil = never spawned.
    var lastSpawnedDay: Date? = nil
}
```

`TaskItem` gains exactly one field so the anti-pileup guard can find live
instances (and nothing else — the task stays otherwise ordinary):

```
var repeatRuleID: UUID? = nil   // which rule spawned this task; nil for hand-added tasks
```

All the fields the old design added to `TaskItem` (`recurrenceRuleData`,
`completionDates`) are **not** present — this is a fresh build from `main`.

### Cadence (pure value type)

Pure, `Codable`, SwiftData-free — same pattern as the rest of `Shared/`:

```
enum RepeatCadence: Codable, Equatable {
    case weekly(Set<Int>)    // Calendar weekdays, 1 = Sun … 7 = Sat; non-empty
    case monthly(Set<Int>)   // days of month, 1…31; non-empty
}
```

Pure helpers (unit-testable without SwiftData):
- `func isScheduled(on day: Date, calendar: Calendar) -> Bool` — is `day` a day
  this cadence fires on (weekday in the set / day-of-month in the set)?
- `func summary() -> String` — "Mon · Wed · Fri", "1st of the month", "1st · 15th"
  (reuses the weekday/ordinal formatting approach).
- JSON `encoded()` / `decode(from:)`, with a typed `cadence` accessor on
  `RepeatRule` mirroring how the app stores small value types as strings.

A monthly day the current month lacks (e.g. 31 in February) simply doesn't fire
that month — no roll-forward, because there's no single "next occurrence" to
compute; spawning is evaluated per-day (see below).

### Spawning engine

A pure decision + a thin store-wiring layer, mirroring `DailyCleanup.decide` /
`StashReturn`:

- **Pure:** `RepeatSpawner.shouldSpawn(rule:, now:, hasOpenInstance:, calendar:) -> Bool`
  Returns true when **all** hold:
  1. `now`'s start-of-day is strictly after `rule.lastSpawnedDay` (always true when
     `lastSpawnedDay` is nil),
  2. there is a scheduled day in the window `(lower, today]`, where `lower` is
     `lastSpawnedDay` if set, otherwise `startOfDay(now) - 1 day` — i.e. today is
     scheduled, or (once the rule has spawned at least once) a scheduled day was
     missed since the last spawn (a single catch-up). A brand-new rule
     (`lastSpawnedDay == nil`) therefore only fires when **today itself** is
     scheduled — it never retroactively adds a task for days before it existed.
  3. `hasOpenInstance == false` — no open task with this `repeatRuleID` exists.

- **Wiring:** `RepeatSpawner.runIfNeeded(in: context, now:)` iterates all
  `RepeatRule`s; for each, computes `hasOpenInstance` (any `TaskItem` with
  `repeatRuleID == rule.id` and `done == false`, stashed or not), and if
  `shouldSpawn`, inserts a `TaskItem(title: rule.name, repeatRuleID: rule.id)` at
  the bottom of Today's open group and sets `rule.lastSpawnedDay = startOfDay(now)`.
  Then `Surfaces.reload()` if anything spawned.

`runIfNeeded` is called from the same places the app already runs its daily
catch-up (app foreground + the foreground midnight timer), right alongside
`DailyCleanup.runIfNeeded` and `StashReturn.runIfNeeded`.

**Why the guard uses "open instance, not done":** a completed spawned task is on
its way out (auto-clear), so it should not block the next spawn; an *open* one
(including one you stashed) means "you still haven't dealt with this," so we don't
pile a second one on top. This is the "if that task is still there, don't do
anything" rule.

### Settings UI

A new **"Repeating"** section in `SettingsView`:

- A row per rule showing its name + cadence summary, e.g. *"Water plants · Mon ·
  Thu."* Tapping a row opens the rule editor.
- An **"Add repeating task"** row → opens the editor on a new blank rule.
- The **rule editor** (a sheet/pushed screen): a name field, a cadence picker
  (Weekly → weekday multi-select; Monthly → day-of-month multi-select), and a
  **Delete** action. Save is disabled until the name is non-empty and at least
  one day is selected. Deleting removes the rule only (spawned tasks stay).

No entry point exists anywhere else — not on tasks, not in the stash, not in the
header. Editing a rule's name/schedule affects only future spawns; existing
spawned tasks are independent and unchanged.

### What is explicitly removed vs. the abandoned branch

Because this builds from `main`, none of the following ship: the self-reopening
`TaskItem` recurrence fields, `finalizeOccurrence`/reschedule-on-complete, the
stash split into Stashed/Repeating sections, the long-press "Repeat…" menu, the
Today repeat badge, and daily/every-N-days cadences.

## Testing

Pure-logic unit tests (no SwiftData), in the existing XCTest style with fixed
calendars:
- `RepeatCadence.isScheduled(on:)` for weekly (each weekday) and monthly
  (present day, absent day like Feb 31 → false).
- `RepeatCadence.summary()` for weekly lists and monthly single/multiple ordinals.
- Codable round-trip of `RepeatCadence`.
- `RepeatSpawner.shouldSpawn`: fires on a scheduled day when no open instance and
  not already spawned today; suppressed when an open instance exists; suppressed
  when already spawned today (`lastSpawnedDay == today`); single catch-up for a
  missed scheduled day; never fires on an unscheduled day.

Store-level tests with an in-memory `ModelContainer` (matching `StashTests`):
- `RepeatSpawner.runIfNeeded` inserts exactly one task titled with the rule name,
  tagged with `repeatRuleID`, and advances `lastSpawnedDay`.
- A second `runIfNeeded` the same day is a no-op; with the prior task still open,
  a later scheduled day is still a no-op; once that task is completed/cleared, the
  next scheduled day spawns again.
- Deleting a rule leaves already-spawned tasks intact.

Settings UI is verified by build + manual check (the codebase does not unit-test
views).

## Out of scope (explicit)

- Daily / every-N-days cadences, end dates, per-task completion history.
- Any "next occurrence" / countdown / forecast surface, and notifications.
- Creating a repeat from an existing task, or any repeat affordance outside
  Settings.
- The centered-title header restyle (separate future cosmetic project).
- The previously-planned tap-to-open task info view.
