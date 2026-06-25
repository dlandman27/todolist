# Stash (snooze tasks out of Today) — Design

**Date:** 2026-06-24
**Status:** Approved, ready for implementation plan

## Problem

The app is a single daily list. Tasks you want to remember but can't act on today
(e.g. "pick up packages tomorrow", or a someday "don't forget this") just sit in the
list, cluttering the sense of "this is what I have to do today." We want a way to set a
task aside without losing it — while keeping the one-list, no-dates, calm-and-simple
identity. The fix is a **stash**: a dateless drawer you tuck tasks into, not a second
list you live in.

## Guiding principle

A *list* is something you actively curate and look at; a *drawer* is write-mostly,
read-rarely. The stash is a drawer: hidden until it holds something, reached through a
small header affordance, never competing with Today for attention. Inside the drawer it
may behave like its own little list (its own clear, its own undo), but it is walled off
from Today.

## Decisions

| Question | Decision |
|----------|----------|
| Model of "later" | Dateless stash (drawer), not a calendar |
| Stash gesture | Swipe an open Today task the opposite way from delete (leading/right edge) |
| Pick how long | Bottom sheet: **Tomorrow** / **Next week** / **Never** |
| Tomorrow | Auto-returns at **local midnight** (start of the next day) |
| Next week | Auto-returns at **local midnight**, 7 days out |
| Never | Indefinite; returns only when manually brought back |
| Doorway | A **bag** icon in the header next to ⋯: outline when empty, filled + count badge when not |
| Open stash | Tap the bag → bottom-sheet modal, opens small, drag up to expand |
| Stash list | Single list sorted by soonest return; each row shows a relative label |
| Return label | "Back tomorrow" / "Back in N days" / "Someday" (Never) |
| Returning item lands | Bottom of the open group in Today (doesn't jump the queue) |
| Stashable tasks | Open tasks only (not completed, not blank drafts) |
| Clear All scope | Today only — the stash is protected |
| Clear Stash | A separate action inside the sheet that empties only the stash |
| Stash undo | Its own rolling undo, self-contained to the sheet, separate from the Today undo |
| Widget / Live Activity | Stashed items are hidden (same as blank drafts) |
| Daily cleanup | Ignores the stash (only clears completed) |

## Design

### Stashing a task (from Today)

Swipe an **open** task on its **leading edge** (the inverse of the trailing-edge
delete) → a **bottom sheet** offers three choices:

- **Tomorrow** — sets the return to **local midnight at the start of the next day**
  (`calendar.startOfDay(for: now) + 1 day`).
- **Next week** — sets the return to **local midnight 7 days out**
  (`calendar.startOfDay(for: now) + 7 days`).
- **Never** — no return date; the item waits in the stash until manually pulled.

Returns are date-boundary based, not relative to the exact time of stashing: an item
stashed "Tomorrow" at 3pm and one stashed at 9pm both return at the same local midnight.

The task immediately leaves Today (and the widget / Live Activity) and appears in the
stash.

### Return mechanics

Timed items (Tomorrow / Next week) carry a return date set to **local midnight** of their
target day, and auto-return once that boundary has passed. This reuses the app's existing
daily catch-up pattern (`MidnightScheduler` + a `DailyCleanup`-style "run if needed" check
on foreground and at midnight): on each check, any stashed item whose `stashReturnDate` is
`<= now` is un-stashed and placed at the **bottom of the open group** in Today. Because the
returns share the midnight boundary with daily cleanup, a single catch-up handles both.
"Never" items (no return date) are never auto-returned.

### Doorway — the bag

A **bag icon** in the title bar, next to the ⋯ menu and gear:

- **Empty stash:** outline bag, no badge.
- **Non-empty:** filled bag with a small count badge ("how many").
- **Tap:** a bottom-sheet modal opens small (a peek) and can be dragged up to expand.

The badge/fill is the "don't let me forget" nudge without showing contents — the core of
"don't show me now, but don't lose it."

### Inside the stash sheet

A single list, **sorted by soonest return** (Never items sort last). Each row:

`[checkbox]  Title                      <relative label>`

The relative label is computed from the return date vs. now:
- returns next day → "Back tomorrow"
- returns later → "Back in N days"
- Never → "Someday"

Row actions (mirroring the main list so there's nothing new to learn):

- **Swipe left (trailing) → Delete.** Undo toast appears *inside the sheet*; restoring
  returns the item to the stash **with its remaining time intact** (not to Today).
- **Swipe right (leading) → Bring back to Today now.** The inverse of stashing.
- **Tap the checkbox → Complete.** Un-stashes the task and marks it done; it then
  follows normal completed handling (sinks in Today / cleared at end of day).
- **Tap the relative label → Re-snooze.** Reopens the Tomorrow / Next week / Never
  picker to change the return (or set Never).
- **Clear Stash** (a control in the sheet — e.g. a ⋯ menu within the sheet) → empties the
  stash, with its own undo.

### Undo (stash)

The stash has its **own** undo, **self-contained to the sheet** and fully separate from
the Today list's rolling undo batch:

- Stash deletes and Clear Stash accumulate into one rolling ~5s undo window (mirroring
  the Today behavior, but scoped to the sheet).
- Restoring returns items to the **stash** with their return date intact — never to
  Today.

### Cross-surface behavior

- **Today list, widget, and Live Activity** all exclude stashed items (the same way they
  exclude blank drafts today). The Lock Screen stays "today only."
- **Clear All / "Delete all"** affects only Today; the stash is untouched.
- **Daily auto-cleanup** only clears completed tasks; stashed (open) items just wait.

## Data model

`TaskItem` gains stash state. Proposed representation (final field shape to be settled in
the plan):

- `isStashed: Bool = false` — whether the task is currently in the stash.
- `stashReturnDate: Date? = nil` — when a stashed item auto-returns; `nil` while stashed
  means **Never** (manual only). Ignored when `isStashed == false`.

New properties default to "not stashed", so existing tasks migrate in place via
SwiftData lightweight migration (no schema version bump needed for additive optional /
defaulted fields).

Filtering / queries:
- **Today** (app `@Query` display + `ModelContext.orderedTasks()` for widget/LA): exclude
  blank drafts **and** `isStashed` items.
- **Stash list:** `isStashed == true`, sorted by `stashReturnDate` ascending with `nil`
  (Never) sorted last.

`TaskSnapshot` must additionally capture `isStashed` and `stashReturnDate` so the stash's
undo restores an item faithfully to the stash with its countdown.

## Edge cases

- **Re-snooze** simply rewrites `stashReturnDate` (or sets Never).
- **Multi-day absence:** if the app isn't opened for several days, the foreground
  catch-up returns all due items at once (consistent with how daily cleanup catches up
  missed days).
- **Completing from the stash:** un-stashes + marks done in one step; the task rejoins
  Today's completed group and is subject to normal end-of-day cleanup.
- **Stashing is unavailable** on completed tasks and blank drafts (only open, real tasks
  show the stash swipe).
- **Returning order:** returned items land at the bottom of the open group via the
  existing `sortOrder = max+1` convention, so they never jump ahead of today's work.

## Testing

Unit-testable logic (in-memory `ModelContext`, matching existing `TaskActionsTests`):
- Stash / un-stash mutations set `isStashed` / `stashReturnDate` correctly.
- Today/widget filtering (`orderedTasks()`) excludes stashed items.
- The stash query returns only stashed items, sorted soonest-first with Never last.
- The return-due check un-stashes items whose `stashReturnDate` has passed and leaves
  future / Never items stashed (pure decide-style function, like `DailyCleanup.decide`).
- The relative-label formatter ("Back tomorrow" / "Back in N days" / "Someday").
- `TaskSnapshot` round-trips stash state (delete a stashed item → restore → still stashed
  with same return date).

UI behaviors (verified by build + on-device): the bag fill/badge, the bottom-sheet pick,
the sheet's swipe actions, and the in-sheet undo toast.

## Out of scope / future

- **Stash via Siri / Shortcuts** — a `StashTaskIntent` mirroring the existing
  `AddTaskIntent` / `CompleteTaskIntent` pattern. Explicitly deferred.
- Absolute-date scheduling / a calendar picker (deliberately rejected — it would break
  the no-dates identity).
- Sub-grouping the stash by return bucket (rejected — reads as sub-lists).
