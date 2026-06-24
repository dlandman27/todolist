# Undo for Clear actions — Design

**Date:** 2026-06-24
**Status:** Approved, ready for implementation plan

## Problem

The two bulk-delete actions — **Clear Completed** and **Clear All** — permanently
delete `TaskItem`s. Their confirmation dialogs even say "This can't be undone."
A mistaken tap (or confirming the wrong dialog) loses tasks with no recovery.

## Scope

In scope:
- **Clear Completed** — undo restores all removed completed tasks.
- **Clear All** — undo restores the entire list.

Explicitly **out** of scope (unchanged):
- Swipe-delete of a single task.
- Midnight auto-cleanup (`DailyCleanup`) — silent, headless, no UI surface.

## Decisions

| Question | Decision |
|----------|----------|
| Which actions | Clear Completed + Clear All only |
| UI mechanism | Bottom toast with an "Undo" button, auto-hides ~5s |
| Undo window | In-memory only; dies when the toast hides (~5s) |
| Confirmation dialogs | Keep both as speed-bumps; fix the now-false wording |
| Restore mechanism | Value snapshots + re-insert (Approach A) |

Rejected restore mechanisms:
- **Soft-delete / tombstone** (`deletedAt` flag): invasive — schema migration plus a
  filter on every read path (app `@Query`, `orderedTasks()`, widget, Live Activity).
  Too heavy for a transient 5-second feature.
- **`ModelContext.undoManager`**: captures everything on the context, hard to scope to
  just these two actions, awkward to wire to a custom toast + timeout.

## Design

### 1. Data layer — `TaskSnapshot` + `TaskActions`

New value type capturing a task's restorable state:

```swift
struct TaskSnapshot {
    let id: UUID
    let title: String
    let done: Bool
    let createdAt: Date
    let completedAt: Date?
    let sortOrder: Int
}
```

`TaskActions` changes (all remain `@discardableResult`):
- `clearCompleted(in:) -> [TaskSnapshot]` — snapshot the completed tasks *before*
  deleting; return them. (Was `-> Int`.)
- `clearAll(in:) -> [TaskSnapshot]` — same for the whole list. (Was `-> Int`.)
- **New** `restore(_ snapshots: [TaskSnapshot], in: ModelContext)` — recreate each
  `TaskItem` from its snapshot, **preserving the original `id`, `title`, `done`,
  `createdAt`, `completedAt`, `sortOrder`**, insert, and save.

The only other caller of `clearCompleted` is `DailyCleanup.runIfNeeded` (midnight
auto-cleanup). It uses the result via `@discardableResult` and ignores it, so the
signature change from `Int` to `[TaskSnapshot]` does not affect it and it shows no toast.

**Why preserve `id` + `sortOrder`:** restoring re-creates the list byte-identical —
same order (open-first, completed sunk via `TaskOrdering`), same completion
timestamps — not merely "the same titles in some order."

### 2. Undo state — in `ListView`

```swift
struct PendingClear { let id = UUID(); let snapshots: [TaskSnapshot]; let message: String }
@State private var pendingClear: PendingClear?
```

- `clearCompleted()` / `clearAll()` set `pendingClear` from the returned snapshots, with
  a count-based `message` (e.g. "Cleared 5 tasks" / "Cleared 1 task"), in addition to
  their existing `withAnimation(.appMotion)`, haptics, `live.refresh()`, and
  `WidgetCenter.shared.reloadAllTimelines()`.
- **Auto-dismiss:** a `.task(id: pendingClear?.id)` modifier sleeps ~5s then sets
  `pendingClear = nil`. Keying on `PendingClear.id` means a *second* clear replaces the
  snapshots and restarts the timer; the previous undo is discarded (matches the
  "dies with the toast" decision). `Task.sleep` cancellation handles the restart.
- **Undo tap:** call `TaskActions.restore(snapshots, in: context)`, then the same
  side-effects (`live.refresh()` + `WidgetCenter.shared.reloadAllTimelines()`) plus a
  confirming haptic (`Haptics.selection()`), then set `pendingClear = nil`.
- **Background:** clear `pendingClear` on scenePhase `.background` so a stale toast never
  greets the user on reopen.

Starting inline in `ListView`. If review finds it bloats the already-large view, extract
a small `@Observable ClearUndoController` — but not pre-emptively (YAGNI for a 5s feature).

### 3. Toast view — new `DailyTodo/Views/UndoToast.swift`

Self-contained view: `message` text on the left, "Undo" button on the right. Styled with
existing theme tokens — `Color.appSurface` background, rounded capsule with a soft shadow,
`Color.brand` for the Undo action, `Color.textPrimary`/`Color.textSecondary` for text.
Slide-up + fade transition driven by the existing `.appMotion` animation (honors
reduce-motion).

**Placement:** the bottom `safeAreaInset(edge: .bottom)` becomes a `VStack` stacking the
toast (when `pendingClear != nil`) *above* the existing `liveActivityButton`, so the toast
never covers the Go-Live pill and the list naturally makes room.

### 4. Confirmation dialogs

Keep both dialogs as deliberate speed-bumps. Replace the now-false "This can't be undone."
message with a calm "You can undo this right after." in both the Clear All and Clear
Completed dialogs.

## Edge cases

- **Second clear while a toast is up:** `pendingClear` is replaced; the `.task(id:)` timer
  restarts; the earlier snapshots are dropped. Acceptable per the toast-lifetime decision.
- **Add a task between clear and undo:** rare. Restored tasks keep their original
  `sortOrder`; after Clear All a newly added task took `sortOrder` 0, so it may interleave
  with restored tasks. Ordering stays deterministic via the `createdAt` tiebreaker in
  `TaskOrdering`. Acceptable; not specially handled.
- **Restore identity:** preserving `id` means any surface keyed on task id (animations,
  Live Activity `LiveTask`) treats a restored task as the same task, not a new one.
- **Midnight cleanup:** out of scope, headless, shows no toast; unaffected by the
  signature change.

## Testing

Unit tests (in-memory `ModelContext`, matching existing `TaskActionsTests` style):
- `clearCompleted` returns snapshots of exactly the completed tasks and leaves only the
  open tasks in the store.
- `clearAll` → `restore` round-trip: count, `id`s, `sortOrder`, `done`, `completedAt` all
  match the originals; `TaskOrdering.ordered(...)` output is identical before-clear vs
  after-restore.
- `clearCompleted` → `restore` puts completed tasks back in their sunk position
  (verified via `TaskOrdering.ordered`).

Manual / optional UITest (view-timing behavior, not unit-testable):
- Toast appears after a clear; tapping Undo restores; toast auto-hides after ~5s; a second
  clear replaces the toast and its undo target.

## Out of scope / future

- Undo for swipe-delete and midnight auto-cleanup.
- Persisting undo across app backgrounding.
- A "recently deleted" history beyond the single most-recent clear.
