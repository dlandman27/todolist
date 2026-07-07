# Live Activity Lifecycle Fix — Design

**Date:** 2026-07-07
**Status:** Approved

## Problem

The pinned-list Live Activity disappears "randomly" during the day. Two causes,
both in `DailyTodo/LiveActivityController.swift`:

1. **8-hour system limit.** iOS ends every Live Activity 8 hours after it was
   *requested*; updates do not extend that clock. `refresh()` only requests a
   new activity when `Activity.activities` is empty, so the activity's death
   time is fixed at first-open + 8h — even if the user is actively using the
   app right before it dies.
2. **Zombie activities.** After the system ends an activity, it can remain in
   `Activity.activities` in the `.ended`/`.dismissed` state for up to 4 hours.
   `refresh()` sees a non-empty list, takes the update branch, and updates the
   dead activity. Reopening the app therefore does *not* bring the pinned list
   back, which is what makes the failure feel random.

## Approach (chosen: Option A + stale date)

Fix the lifecycle locally — no push infrastructure. The activity should only
ever be missing if the phone hasn't run the app (foreground or refresh-calling
interaction) for 8+ hours, and opening the app must always resurrect it.

Rejected alternatives: APNs push-to-start (requires a server; overkill for a
personal app), stale-date-only (doesn't prevent the disappearance).

## Design

### 1. Pure decision logic: `Shared/LiveActivityPlanner.swift`

Follows the `RepeatSpawner.shouldSpawn` pattern: all branching lives in a pure,
unit-testable function; ActivityKit calls stay thin.

```swift
enum LiveActivityAction: Equatable {
    case start          // request a fresh activity (none usable)
    case update         // update the existing live activity
    case restart        // end existing + request fresh (resets the 8h clock)
    case none           // user opt-out or system-disabled
}

struct ActivitySnapshot {
    var isLive: Bool      // activityState is .active or .stale
    var startedAt: Date?  // recorded at request time; nil if unknown
}

enum LiveActivityPlanner {
    /// maxAge default: 1 hour.
    static func action(
        userEnabled: Bool,
        systemEnabled: Bool,
        activities: [ActivitySnapshot],
        now: Date,
        maxAge: TimeInterval
    ) -> LiveActivityAction
}
```

Rules, in order:
- `!userEnabled || !systemEnabled` → `.none`
- no snapshot with `isLive` → `.start`
- live snapshot with `startedAt == nil` (unknown age) → `.restart`
- live snapshot older than `maxAge` → `.restart`
- otherwise → `.update`

### 2. Controller changes: `DailyTodo/LiveActivityController.swift`

- Record the request time in App Group defaults (`liveActivityStartedAt`)
  whenever an activity is requested; clear it on `stop()`.
- `refresh()` maps `Activity<TodoActivityAttributes>.activities` to
  `[ActivitySnapshot]`, asks the planner, then executes the action. `.start`
  and `.restart` also end all existing activities (live or dead) before
  requesting, so duplicates can't accumulate.
- `syncRunningState()` / `isRunning` counts only `.active`/`.stale` activities,
  so the Customize toggle reflects reality after a silent system kill.
- Every `ActivityContent` gets `staleDate = start + 8h` so if the system does
  outlive our updates, the widget can render a stale look instead of stale
  checkmarks.

### 3. Widget: stale rendering

In the Live Activity view (DailyTodoWidgets), when `context.isStale`, dim the
content (reduced opacity) — a visible cue that the list is no longer live.

### 4. Tests: `DailyTodoTests/LiveActivityPlannerTests.swift`

Pure planner tests, no ActivityKit:
- disabled (user or system) → `.none`, even with a live activity present
- no activities → `.start`
- only dead activities → `.start`
- live activity, 30 min old → `.update`
- live activity, 2 h old → `.restart`
- live activity, unknown start date → `.restart`
- boundary: exactly `maxAge` → `.restart` (strictly-older-or-equal restarts)
- dead + fresh live activity together → `.update` (the live one wins)

## Out of scope

- APNs push-to-start / remote updates
- Any change to what the Live Activity displays (beyond stale dimming)
