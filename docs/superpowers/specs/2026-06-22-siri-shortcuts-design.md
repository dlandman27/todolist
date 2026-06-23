# Siri Shortcuts & App Shortcuts — Design

**Date:** 2026-06-22
**Status:** Approved (design), pending implementation plan

## Goal

Let the user drive the Daily to-do list by voice (Siri) and via the Shortcuts app,
without launching the app. Four capabilities, all available as ready-made "Hey Siri"
phrases *and* as composable actions in the Shortcuts app:

1. **Add a task** — capture a new to-do.
2. **Complete a task** — check off an existing open task (pick from a list).
3. **Ask what's left** — Siri reads back the open tasks.
4. **Clear** — clear completed, or clear all.

## Approach

Built on Apple's **App Intents** framework (the same one `ToggleTaskIntent` already
uses for the widget / Live Activity), plus an **`AppShortcutsProvider`** that registers
spoken phrases. Each `AppIntent` is automatically an action in the Shortcuts app; the
provider layers zero-setup Siri phrases on top. No SiriKit, no new entitlement, no
Info.plist changes.

All persistence reuses the existing App Group SwiftData store via
`ModelContext(TaskStore.shared)`. All mutations route through `TaskActions` (the shared
helper that already holds `clearCompleted` / `clearAll`) so the app, widget, and intents
share one implementation and one set of side effects.

The app's display name is **"Daily"**, which appears in every spoken phrase (Siri
requires the app name in each phrase).

## Components

New code lives in the **main app target** (e.g. `DailyTodo/Siri/`), except the shared
mutation helpers which go in `Shared/TaskActions.swift`. The `AppShortcutsProvider` must
be in the app target.

### `TaskEntity: AppEntity`
A Siri/Shortcuts-facing representation of a `TaskItem`.
- `id: UUID`
- `title: String` (used for `DisplayRepresentation`)
- `typeDisplayRepresentation`: "Task"
- Backed by `TaskEntityQuery`.

### `TaskEntityQuery: EntityQuery`
Reads from the shared store.
- `entities(for ids: [UUID]) -> [TaskEntity]` — resolve specific tasks by id.
- `suggestedEntities() -> [TaskEntity]` — returns **open** tasks only (the
  disambiguation pick-list for Complete). Excludes blank drafts and completed tasks.
- Ordering follows `TaskOrdering.ordered` (open group order).

### Intents

All mutating intents call into `TaskActions`, then refresh surfaces via
`LiveActivityBridge.updateRunningActivities()` and `WidgetCenter.shared.reloadAllTimelines()`
(mirroring `ToggleTaskIntent`).

| Intent | Parameters | Behavior | Spoken result |
|--------|-----------|----------|---------------|
| `AddTaskIntent` | `title: String` | Insert a new task with `sortOrder = max(open sortOrder) + 1` (same rule as the app's `addTask`). Returns the created `TaskEntity`. | "Added milk." |
| `CompleteTaskIntent` | `task: TaskEntity` (open tasks → Siri pick-list) | Mark the task done via `toggleDone()` (no-op guard if already done). | "Completed milk." / if no open tasks: "Your list is empty." |
| `OpenTasksIntent` | none | Fetch open tasks. Returns `[TaskEntity]` (composable) plus dialog. | "You have 3 tasks: milk, call mom, pay rent." / "Your Daily list is empty." |
| `ClearCompletedIntent` | none | `TaskActions.clearCompleted`. | "Cleared 2 completed tasks." / "No completed tasks to clear." |
| `ClearAllIntent` | none | **Confirms first** (`requestConfirmation`: "Delete all 5 tasks?"), then `TaskActions.clearAll`. | "Cleared your list." |

`isDiscoverable = true` and clear `title` / `parameterSummary` on each so they read well
in the Shortcuts editor.

### `DailyShortcuts: AppShortcutsProvider`
Registers an `AppShortcut` per intent. Phrases (each includes `\(.applicationName)`):

- **Add:** "Add to Daily", "Add a task to Daily"
- **Complete:** "Complete a task in Daily", "Check off a task in Daily"
- **What's left:** "What's on my Daily list", "What's left in Daily"
- **Clear completed:** "Clear completed in Daily"
- **Clear all:** "Clear my Daily list"

## Interaction details

- **Add by voice:** A free-text parameter can't be embedded in a fixed Siri phrase, so
  "Add to Daily" triggers the intent and Siri prompts *"What's the task?"* (via the
  parameter's request-value dialog); the user speaks the title. In the Shortcuts app the
  title is passed directly as an action input.
- **Complete:** Uses Siri's native disambiguation over `suggestedEntities()` (open
  tasks). No fuzzy name matching.
- **Clear all** is the only intent that confirms before acting; the others run directly
  (cheap or reversible enough).

## Shared refactor (`Shared/TaskActions.swift`)

Add two helpers alongside the existing clear functions, operating on a `ModelContext`:

- `add(title:in:) -> TaskItem` — trims the title, computes `sortOrder = max(open) + 1`,
  inserts, saves. (Factor the ordering rule currently inline in `ListView.addTask` so
  both call the same code.)
- `complete(id:in:)` / `setDone(id:in:)` — fetch by id, `toggleDone()` if open, save.

`ListView.addTask` is updated to call `TaskActions.add` so there's a single source of
truth for insertion + ordering.

## Side effects

Every mutating intent (`Add`, `Complete`, `ClearCompleted`, `ClearAll`) refreshes the
Live Activity and reloads widget timelines after saving, identical to `ToggleTaskIntent`.

## Configuration

- **No new entitlement.** App Shortcuts are auto-discovered from the provider.
- **No Info.plist / `NSSiriUsageDescription`.** Those are for legacy SiriKit, not App
  Intents.
- **No signing/capability changes.**

## Testing

- Extend `DailyTodoTests/TaskActionsTests.swift` to cover the new `TaskActions.add`
  (title trimming, sortOrder assignment) and complete-by-id helpers, using an in-memory
  `ModelContainer` (matching the existing test pattern).
- The intents are thin wrappers over `TaskActions`; their `perform()` logic is exercised
  indirectly through the helper tests.
- Final manual verification pass: each phrase via Siri, and each action composed in the
  Shortcuts app, on the simulator/device.

## Out of scope

- Fuzzy name matching for Complete (pick-list chosen instead).
- Editing or reordering tasks via Siri.
- Parameterized Siri phrases for free-text title (Siri prompt used instead).
