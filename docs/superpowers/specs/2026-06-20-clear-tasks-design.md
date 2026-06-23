# Clear Tasks (Mass Deletion) — Design

**Date:** 2026-06-20
**Status:** Approved, ready for implementation plan

## Summary

Add manual bulk-deletion to the list: **Clear Completed** (remove all done tasks)
and **Clear All** (remove every task). Triggered from a new "list options" menu
(⋯) in the header. The deletion logic is extracted into a shared `TaskActions`
util so the upcoming midnight auto-delete feature (Issue 1) reuses the exact same
code path.

This is the "Clear Completed" feature deliberately deferred earlier, now designed
"in general."

## Goals

- Let the user clear completed tasks in one action.
- Let the user clear the entire list in one action, guarded by confirmation.
- Keep the minimal header clean and give it a stable information architecture.
- Make the deletion logic reusable by Issue 1 (auto-delete at midnight).

## Non-Goals

- Undo. (Confirmation guards the destructive action; no undo stack.)
- Sorting. The ⋯ menu is *structured* to host a future "Sort By" section, but
  sorting itself is a separate feature designed later.
- Selecting/deleting arbitrary subsets of tasks (multi-select edit mode).

## Information Architecture

The header gets a stable two-button ceiling:

- **⚙ Settings** (existing) — app-wide preferences (haptics, theme, auto-delete).
- **⋯ List options** (new) — operations on *this list*.

Conceptual split: **⚙ = app, ⋯ = this list.** Future list-level options (e.g.
Sort) go inside ⋯ as new sections — never as new header buttons.

The ⋯ menu uses sections so it scales:

```
⋯ menu
  (future) Sort By ▸        ← not built now; section reserved
  ──────────────
  Clear Completed
  Clear All  (destructive)
```

## Components

### 1. `TaskActions` — shared deletion util (`Shared/TaskActions.swift`)

A small enum operating on a `ModelContext`. Pure deletion + persistence; no UI.

- `clearCompleted(in context: ModelContext) -> Int`
  Deletes all tasks where `done == true`. Returns the number deleted.
- `clearAll(in context: ModelContext) -> Int`
  Deletes every task. Returns the number deleted.

Each function:
1. Fetches the relevant tasks (reusing `allTasks()`).
2. Deletes them and saves the context.
3. Returns the count.

**Side-effect refresh** (Live Activity + widget reload) is the caller's
responsibility, kept out of `TaskActions` so it stays pure and testable, and so
Issue 1 can decide its own refresh timing. The view layer calls the same refresh
it already uses elsewhere (`LiveActivityController.shared.refresh()` +
`WidgetCenter.shared.reloadAllTimelines()`).

> Rationale: matches the existing `TaskOrdering` / `TaskStyle` pattern — one place
> per concern, shared between app and (future) callers. Issue 1's midnight purge
> calls `TaskActions.clearCompleted(in:)` directly.

### 2. List options menu (`ListView`)

- A new `ellipsis.circle` button placed **left of the gear** in `titleHeader`.
- Rendered as a SwiftUI `Menu` with a sectidon containing:
  - **Clear Completed** — runs immediately.
  - **Clear All** — `role: .destructive`; opens a confirmation dialog.
- **Smart enablement:**
  - "Clear Completed" disabled when no completed tasks exist.
  - "Clear All" disabled when the list is empty.
  - So the menu never offers a no-op.

### 3. Confirmation

- **Clear All** presents a `confirmationDialog`:
  "Delete all N tasks? This can't be undone." with a destructive confirm button
  and Cancel. N is the current task count.
- **Clear Completed** has no dialog (low-risk; only removes done items).

### 4. Feedback

- Both actions wrap the deletion in `withAnimation(.appMotion)` so rows animate out
  with the app's shared spring.
- Both fire `Haptics.notify(.warning)` (the existing haptics util, gated by the
  user's setting), consistent with swipe-to-delete.

## Data Flow

```
User taps ⋯ → Clear Completed
   → withAnimation(.appMotion) { TaskActions.clearCompleted(in: context) }
   → Haptics.notify(.warning)
   → live.refresh(); WidgetCenter.reloadAllTimelines()

User taps ⋯ → Clear All
   → confirmationDialog
       → Confirm: withAnimation(.appMotion) { TaskActions.clearAll(in: context) }
                  → Haptics.notify(.warning)
                  → live.refresh(); WidgetCenter.reloadAllTimelines()
       → Cancel: no-op
```

## Testing

- **`TaskActions` unit tests** (pure, in-memory `ModelContext`):
  - `clearCompleted` removes only done tasks, leaves open ones, returns correct count.
  - `clearCompleted` on a list with no completed tasks deletes nothing, returns 0.
  - `clearAll` empties the store, returns the full count.
  - `clearAll` on an empty store returns 0.
- **Manual / UI:** menu item enablement reflects list state; Clear All dialog
  appears and Cancel aborts; widgets/Live Activity reflect the cleared list.

## Reuse for Issue 1

Issue 1 (auto-delete completed at midnight) will call
`TaskActions.clearCompleted(in:)` from its purge path, guaranteeing the manual and
automatic clears behave identically. No deletion logic is duplicated.
