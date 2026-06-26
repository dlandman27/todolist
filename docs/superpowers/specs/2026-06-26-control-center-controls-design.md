# Control Center controls for 1List

**Date:** 2026-06-26
**Status:** Approved — ready for implementation planning

## Goal

Add iOS 18+ Control Center controls to 1List (DailyTodo) so the user can act on
their list from anywhere via Control Center, the Lock Screen, or the Action
button — without the existing app, widget, or Live Activity behavior changing.

Three controls ship:

1. **Quick Add** — tap opens the app straight into new-task entry.
2. **Tasks Left** — shows the open-task count; tap opens the app to the list.
3. **Stashed** — shows the stashed-task count; tap opens the **stash drawer**.

## Constraints & context

- Control Center controls (`ControlWidget`) require **iOS 18.0+**. The app's
  deployment target is **iOS 17.0** (`project.yml`) and stays there. All control
  code is gated `@available(iOS 18.0, *)`; the controls are added to the bundle
  behind an availability check so the extension still builds and runs on iOS 17.
- Controls live in the existing `DailyTodoWidgets` app-extension target, which
  already compiles `Shared/` and hosts the widget + Live Activity.
- Controls read the same shared SwiftData store the widget uses
  (`ModelContext(TaskStore.shared)`), via the App Group.
- Deep linking already exists: `dailytodo://add` →
  `DailyTodoApp.onOpenURL` → `Router.addRequested` → `ListView` opens add mode.
  We extend this exact pattern for stash.

## Design

### Control 1 — Quick Add

- A `ControlWidgetButton` whose action is the system
  `OpenURLIntent(DeepLink.addURL)` (`dailytodo://add`).
- Reuses the existing add deep link end-to-end — **no app-side changes** for
  this control.
- Icon: `plus.circle` (or `plus`). Label: "Add Task".

### Control 2 — Tasks Left

- A `ControlWidget` backed by a `ControlValueProvider` returning the open-task
  count: `ModelContext(TaskStore.shared).orderedTasks().filter { !$0.done }.count`.
  (`orderedTasks()` already excludes stashed and blank tasks.)
- Display: count + "left" (e.g. "3 left"); icon `checklist`.
- Tap opens the app to the plain list (not add mode). Action: a dedicated
  `OpenAppIntent` — an `AppIntent` with `static var openAppWhenRun = true` and an
  empty `perform()` returning `.result()`. The app launches to its default
  screen (the list); no deep link, no router flag.

### Control 3 — Stashed

- Same shape as Tasks Left: a `ControlValueProvider` returning
  `ModelContext(TaskStore.shared).stashedTasks().count`.
- Display: stash count; icon `archivebox`.
- Tap opens the **stash drawer** via a new deep link (see below).

### New deep link: `dailytodo://stash`

Mirrors the existing add deep link:

- `DeepLink` (in `Shared/AppGroup.swift`) gains `stashHost = "stash"` and
  `stashURL`.
- `Router` (in `DailyTodo/DailyTodoApp.swift`) gains `var stashRequested = false`.
- `DailyTodoApp.onOpenURL` routes `host == DeepLink.stashHost` →
  `router.stashRequested = true`.
- `ListView` adds `.onChange(of: router.stashRequested)` that, when true, sets
  the existing `@State showStash = true` and resets the flag — exactly mirroring
  the `addRequested` handler at `ListView.swift:144`.

### Keeping control values fresh

Controls do not refresh on their own. A new shared helper centralizes the reload:

- New `Shared/ControlReload.swift` exposing e.g.
  `ControlReload.reload()` which calls `ControlCenter.shared.reloadControls(...)`
  for the control kinds, guarded by `if #available(iOS 18.0, *)`.
- Call it wherever the code already reloads widgets:
  - `refreshSurfaces()` in `DailyTodo/Siri/TaskIntents.swift`
  - `ToggleTaskIntent.perform()` in `Shared/ToggleTaskIntent.swift`
  - any app mutation path that currently calls
    `WidgetCenter.shared.reloadAllTimelines()`.

Because reloads always already happen next to widget reloads, this is a
mechanical "add one sibling call" change with a single source of truth.

## Files

**New**
- `DailyTodoWidgets/TodoControls.swift` — the three `ControlWidget` structs and
  their `ControlValueProvider`s.
- `Shared/ControlReload.swift` — availability-gated reload helper.

**Edited**
- `DailyTodoWidgets/DailyTodoWidgetsBundle.swift` — add the controls to the
  `WidgetBundle` (availability-gated).
- `Shared/AppGroup.swift` — add `stashHost` / `stashURL` to `DeepLink`.
- `DailyTodo/DailyTodoApp.swift` — add `Router.stashRequested`; route the new
  host in `onOpenURL`.
- `DailyTodo/Views/ListView.swift` — `.onChange(of: router.stashRequested)` →
  open the stash sheet.
- Reload call sites listed above (`TaskIntents.swift`, `ToggleTaskIntent.swift`,
  plus app mutation paths).

## Out of scope (YAGNI)

- No in-Control-Center text entry for Quick Add (Control Center can't host a text
  field; a titleless task isn't useful). Quick Add opens the app instead.
- No toggle-style controls; all three are buttons / value displays.
- No new widget families or Live Activity changes.

## Testing

- **Logic:** the count providers are thin wrappers over `orderedTasks()` /
  `stashedTasks()`, both already covered. Add a focused test asserting the
  open-count and stashed-count computations match expectations for a known
  fixture (in `DailyTodoTests`, no UI needed).
- **Manual / device:** add each control in Control Center; verify Quick Add opens
  add mode, Tasks Left shows the open count and opens the list, Stashed shows the
  stash count and opens the stash drawer; mutate the list and confirm counts
  refresh.
- Build must still succeed for the iOS 17 deployment target with the controls
  availability-gated.
