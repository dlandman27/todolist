# Manual Priority Sorting — Design

**Date:** 2026-06-21
**Status:** Approved

## Goal

Let the user assign priority to tasks by manually reordering them in the list
(drag to move). The Live Activity and widget show the top 3 items by this
priority. The invariant throughout: **completed tasks always sort below open
tasks.**

## Requirements

1. Open tasks are ordered by a user-controlled manual priority.
2. The user reorders by long-press-dragging a row (always on — no edit mode).
3. Completed tasks always appear below all open tasks.
4. Completed tasks are locked: they keep their current ordering (by completion
   time) and cannot be dragged.
5. Re-opening (un-checking) a completed task returns it to its original
   priority spot among the open tasks.
6. The Live Activity and widget show the top 3 items by priority.

## Data Model

Add a stored property to `TaskItem` (`Shared/TaskItem.swift`):

```swift
/// User-assigned priority within the open group. Lower sorts first.
/// Untouched by completion, so a re-opened task keeps its spot.
var sortOrder: Int = 0
```

- Default `0` enables SwiftData lightweight migration with no manual backfill.
- This field **is** the priority. Completing/re-opening a task never modifies
  it, which satisfies requirement 5 for free.
- New tasks are assigned `maxSortOrder + 1` (across all tasks) so they append to
  the bottom of the open group — matching today's "new task goes last" behavior.

## Ordering

`TaskOrdering.ordered` (`Shared/TaskOrdering.swift`) becomes:

- **Open** tasks (`!done`): sorted by `sortOrder` ascending, with `createdAt`
  ascending as a tiebreaker.
- **Completed** tasks (`done`): sorted by `completedAt` ascending (unchanged).
- Returns `open + completed`, so the open-above-completed rule is enforced
  structurally.

The `createdAt` tiebreaker means existing tasks (all `sortOrder = 0` after
migration) retain their current relative order until the user first drags
something. No migration backfill step is required.

## Reorder Interaction

Long-press-drag, always on, via SwiftUI `List`'s `.onMove` in
`DailyTodo/Views/ListView.swift`:

- Apply `.moveDisabled(...)` to rows that are completed **or** blank drafts, so
  neither can be picked up.
- The move handler:
  1. Receives `IndexSet` source and `Int` destination over the displayed
     `orderedTasks` array.
  2. Clamps the destination into the open range so an open task can't be dropped
     below the completed divider.
  3. Reorders the open subarray accordingly.
  4. Renumbers all open tasks `sortOrder = 0…n` in their new order.
  5. Saves the context, then refreshes the Live Activity and reloads widget
     timelines (same pattern as existing mutations).

Completed tasks keep their existing `sortOrder` values; any overlap with the
renumbered open range is harmless because ordering partitions by `done` first.

### New task assignment

`addTask()` sets the new `TaskItem`'s `sortOrder` to `maxSortOrder + 1` (max
across all existing tasks, or `0` if none).

## Live Activity & Widget

No new logic. Both surfaces already render
`TaskOrdering.ordered(...).prefix(3)` (the lock-screen Live Activity, the
Dynamic Island expanded view, and the home-screen widget via
`ModelContext.orderedTasks()`). Once `ordered` respects `sortOrder`, they
automatically reflect manual priority. The `prefix(3)` cap is already in place.

## Testing

Pure-function tests in `DailyTodoTests/TaskLogicTests.swift`:

- Open tasks sort by `sortOrder`; `createdAt` breaks ties when `sortOrder` is
  equal.
- Completed tasks always sort below open tasks, ordered by `completedAt`.
- A re-opened task (its `sortOrder` preserved) returns to its priority spot
  among the open tasks.
- The reorder helper clamps an open task's destination at the completed divider
  and renumbers the open group correctly.

## Files Touched

- `Shared/TaskItem.swift` — add `sortOrder` property + init parameter.
- `Shared/TaskOrdering.swift` — sort open by `sortOrder` then `createdAt`.
- `DailyTodo/Views/ListView.swift` — `.onMove` + move handler, `.moveDisabled`
  on completed/blank rows, `sortOrder` assignment in `addTask()`.
- `DailyTodoTests/TaskLogicTests.swift` — ordering and reorder tests.
