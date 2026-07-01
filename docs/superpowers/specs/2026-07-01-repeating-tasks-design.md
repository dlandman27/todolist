# Repeating Tasks — Design

**Date:** 2026-07-01
**Status:** Approved, ready for implementation plan

## Problem

The app is a single, dateless daily list where completed tasks auto-clear at end of
day. Recurring chores ("water plants every 3 days", "gym Mon/Wed/Fri", "pay rent on the
1st") have to be re-typed every time. We want tasks that come back on a schedule —
without adding a calendar, times of day, or a second list you have to live in. Repeats
should feel like the natural extension of the mechanism the app already has for
"hidden now, returns on a date": the stash.

## Guiding principle

A repeat is a normal task that knows how to reschedule itself. It rolls over until it's
done, and when it's done it doesn't vanish — it waits for its next date. The "waiting"
state is exactly what the stash already models (`isStashed` + `stashReturnDate` +
`StashReturn` re-opening), so repeats reuse it rather than inventing a parallel system.
Day-granular only: the app has no times, and repeats don't either.

## Decisions

| Question | Decision |
|----------|----------|
| Model | Reuse the stash for the "waiting between occurrences" state; a repeat is one `TaskItem` carrying a recurrence rule (Approach A) |
| Schedules | **Every N days** (N≥1, includes "every day"), **Weekly** on a set of weekdays, **Monthly** on a set of days-of-month |
| End condition | Optional "Ends on" date; `nil` = repeats forever |
| Missed day (unfinished at end of day) | **Rolls over until done** — stays open in Today; the next occurrence only starts once it's completed |
| Interval anchoring | **Every N days** is anchored to *completion* (next = completed date + N days) |
| Weekly / monthly anchoring | Calendar-anchored (a Monday task stays Monday even if finished Tuesday) |
| Between occurrences | Lives in the **stash**, which is split into a "Stashed" section (one-off) and a "Repeating" section |
| Completion history | **Per repeating task** — each keeps its own list of completion dates; deleting the task ("all instances") clears its history. One-off tasks still auto-clear with no history. |
| Configure a repeat | Long-press a Today task → **Repeat…** → recurrence editor sheet; also creatable from the stash's Repeating section |
| Repeat badge | Small `repeat` glyph on repeating rows in Today and in the stash |
| Widget / Live Activity | Unchanged — a due repeat is just a normal open task; not-due repeats are hidden (already excluded as stashed) |
| Notifications | Out of scope (no notification infra today) |
| Time of day | Out of scope — repeats are day-granular |
| Tap-to-open task info view | Out of scope here; planned as the **immediate follow-up**, and it will absorb the recurrence editor as one of its rows |

## Design

### Data model

Add one field to `TaskItem` (SwiftData `@Model`, CloudKit-backed, so it must be optional
with a default):

- `recurrenceRuleData: String? = nil` — `nil` means the task does not repeat. Stores a
  `RecurrenceRule` value type encoded as JSON. Keeping the rule out of the `@Model` as a
  `Codable` value type keeps recurrence logic pure and unit-testable, and keeps the
  persisted attribute a plain optional `String` (CloudKit-safe).

Add the completion history. Preferred:

- `completionDates: [Date] = []` — appended each time an occurrence is finalized as done.

  SwiftData stores a scalar array as a single attribute; the `= []` default keeps it
  CloudKit-compatible. If CloudKit rejects the array attribute in practice, fall back to
  `completionHistoryData: String? = nil` (JSON-encoded `[Date]`), mirroring
  `recurrenceRuleData`. The plan should verify the array form against the CloudKit
  container before committing to it.

Everything else is reused as-is: `isStashed`, `stashReturnDate`, `done`, `completedAt`,
`sortOrder`.

### Recurrence rule (pure value type)

```
enum Frequency: Codable, Equatable {
    case everyNDays(Int)          // N >= 1; 1 == every day
    case weekly(Set<Int>)         // weekdays, Calendar's 1=Sun ... 7=Sat
    case monthly(Set<Int>)        // days of month, 1...31
}

struct RecurrenceRule: Codable, Equatable {
    var frequency: Frequency
    var endDate: Date?            // nil == forever; inclusive last allowed day
}
```

Pure, testable core — in the spirit of `DailyCleanup.decide` and `StashReturn.due`:

```
func nextOccurrence(after completedDate: Date, calendar: Calendar = .current) -> Date?
```

- **everyNDays(N):** `startOfDay(completedDate) + N days`.
- **weekly(days):** the earliest `startOfDay` strictly after `completedDate` whose weekday
  is in `days`.
- **monthly(days):** the earliest `startOfDay` strictly after `completedDate` whose
  day-of-month is in `days`. A month lacking a selected day (e.g. day 31 in April) simply
  skips it and rolls to the next month that has it.
- Returns `nil` if the computed date is after `endDate` — the recurrence is finished.

All returned dates are `startOfDay`, matching the stash's date-boundary model.

### Lifecycle

Open (unfinished) repeating tasks need **no** new code: daily cleanup only purges *done*
tasks, so an open repeat rolls over for free.

The change is at the point a repeating task is finalized as done. This happens in two
places, both routed through one helper `TaskActions.finalizeOccurrence(_:in:)`:

1. **Daily cleanup** (`DailyCleanup` / `TaskActions.clearCompleted`): partition done tasks
   into repeating (rule present) vs normal.
   - Normal → deleted, exactly as today.
   - Repeating → `finalizeOccurrence`.
2. **Complete-from-stash** (`StashSheet.complete`) when the completed task is a repeat →
   `finalizeOccurrence` instead of leaving it completed.

`finalizeOccurrence(task)`:

1. Append `task.completedAt` (falling back to now) to `task.completionDates`.
2. Compute `next = rule.nextOccurrence(after: completedAt)`.
3. If `next` is `nil` (past end date) → the recurrence is over; **delete** the task like a
   normal finished task (its history goes with it).
4. Else set `done=false`, `completedAt=nil`, and:
   - `next` is in the future → `isStashed=true`, `stashReturnDate=next` (drops into the
     stash's Repeating section; existing `StashReturn` re-opens it into Today on that day).
   - `next` is already due (e.g. a daily repeat whose next day is the current new day) →
     re-open in place in Today (`isStashed=false`), no stash hop.

Un-checking a repeat before it is finalized records nothing — history is written only at
finalization, so there's no toggle-unwind bookkeeping.

Deleting a repeating task removes it and its `completionDates` (this is "delete all
instances"). `TaskSnapshot` is extended to carry `recurrenceRuleData` and
`completionDates` so delete → undo of a repeat is lossless.

### UI

**Recurrence editor sheet** (self-contained, reusable by the future task-info view):

- Frequency segmented control: **Every N days** / **Weekly** / **Monthly**.
  - Every N days → a stepper/number for N.
  - Weekly → a 7-day weekday multi-select (S M T W T F S).
  - Monthly → a 1–31 day-of-month multi-select grid.
- **Ends** row: **Never** / **On date** (date picker).
- A minimal history readout: "Done N times · last on <date>" (the full list lives in the
  future task-info view).
- **Remove repeat** action (turns it back into a normal one-off task; keeps the task and
  its title, drops the rule and history).

**Entry points:**

- Long-press a Today task → context menu **Repeat…** opens the editor for that task.
- The stash's **Repeating** section has an "add repeating task" affordance that creates a
  blank repeating task and opens the editor.

**Repeat badge:** a small `repeat` SF Symbol on repeating rows in Today and in the stash
(alongside the title).

**Stash split:** `StashSheet` shows two sections:

- **Stashed** — one-off stashed tasks (`recurrenceRuleData == nil`), current behavior.
- **Repeating** — tasks with a rule, each row showing its schedule summary (e.g. "Every 3
  days", "Mon · Wed · Fri", "1st of the month") and next date.

The stash's existing per-sheet undo, add, delete, and menu actions continue to work across
both sections.

## Testing

Pure-logic unit tests (no SwiftData needed), following the existing `DailyCleanup` /
`StashReturn` test style:

- `RecurrenceRule.nextOccurrence` for each frequency, including: every-day, every-N-days,
  weekly across a week boundary, monthly skipping a too-short month, and `endDate`
  producing `nil`.
- Round-trip `Codable` encode/decode of `RecurrenceRule`.
- Cleanup partition: a done repeat reschedules (stash vs in-place) while a done one-off is
  deleted; a done repeat past its end date is deleted.
- `finalizeOccurrence` appends exactly one history entry per finalization and none on
  un-check-before-finalize.
- Snapshot/restore round-trips the rule and history.

Widget snapshot / Live Activity behavior is unchanged and needs no new tests beyond
confirming not-due repeats stay hidden (they're stashed).

## Out of scope (explicit)

- Notifications / reminders when a repeat appears.
- Per-repeat time of day.
- A global completed-tasks archive (history is per repeating task only).
- The tap-to-open **task info view** — planned as the immediate next feature; it will
  reuse the recurrence editor sheet built here.
