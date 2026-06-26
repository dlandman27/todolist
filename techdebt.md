# Tech Debt & Known Issues

Outstanding items from the code audits (3-reviewer pass + external review), with the
already-fixed and false-positive items removed. Each has a location, why it matters, and a
fix direction. Effort: **S** = trivial, **M** = moderate.

> Already shipped (for context, don't redo): undo for delete/clear with rolling 5s window +
> swipe-to-dismiss; `toggle()` re-syncs `isRunning`; checkbox VoiceOver label; Reduce-Motion
> `LiveDot`; blank-draft excluded from "Delete all" + Siri counts.
>
> Verified NOT bugs (don't chase): midnight cleanup already calls `live.refresh()` at every
> `runDailyCleanup()` site; "1List" in Siri summaries is correct branding; `add()` counting
> completed tasks in `sortOrder` is intentional (has a passing test).

---

## Small correctness quick-hitters (mechanical, low risk)

- [ ] **Log failed saves (S).** Every `try? context.save()` swallows errors silently — a
  disk-full / corruption / migration failure drops the user's edit with no trace, surfacing
  only as lost data on next launch. Sites: `Shared/TaskActions.swift:40,53,64,95`,
  `DailyTodo/Views/TaskRow.swift:113,124`, `DailyTodo/Views/ListView.swift:404`.
  Fix: add a `ModelContext.saveOrLog()` helper (in `Shared/TaskStore.swift` beside the other
  extension) that `do/catch`es and logs; replace the `try?` sites with it.

- [ ] **`restore()` unique-id upsert guard (S).** `TaskActions.restore` re-inserts deleted
  tasks carrying their original `@Attribute(.unique)` id. SwiftData treats a colliding unique
  key as a silent *upsert*, so an undo racing a re-add could overwrite a live task's contents.
  Low probability, cheap guard. `Shared/TaskActions.swift:80-94`.
  Fix: build a `Set` of existing ids first; `for snap in snapshots where !existing.contains(snap.id)`.
  Testable: insert a task, restore a snapshot with the same id, assert no duplicate / no overwrite.

- [ ] **Cleanup marker written before purge is confirmed (S).** `DailyCleanup.runIfNeeded`
  writes the day-marker (`defaults?.set(result.newMarker, …)`) *before* running the purge,
  so if the purge's save silently failed the marker still advances and it won't retry.
  `Shared/DailyCleanup.swift:53-57`. Fix: move the marker write after the purge block. (Full
  retry-on-failure needs `clearCompleted` to report save success — out of quick-hitter scope;
  pairs with the "log failed saves" item.)

- [ ] **Siri Clear-All "No" returns a generic error (S).** `ClearAllIntent.perform`'s
  `try await requestConfirmation(...)` throws when the user declines, surfacing as a generic
  Siri error instead of a clean cancel. `DailyTodo/Siri/TaskIntents.swift:121-123`.
  Fix: wrap in `do { try await requestConfirmation(...) } catch { return .result(dialog: "OK, cancelled.") }`.

- [ ] **Siri says "Completed X" even when already done (S).** `CompleteTaskIntent` reports
  success even if `TaskActions.complete` no-oped on an already-done task.
  `DailyTodo/Siri/TaskIntents.swift:49-56`. Fix: detect the already-done case (check `task.done`
  before completing, or have `complete()` signal whether it changed) and say
  "'X' is already done."

- [ ] **`runDailyCleanup()` + `midnight.start()` double-run on launch (S).** Both the `.task`
  and `onChange(scenePhase == .active)` blocks run the same three lines, so they can fire twice
  close together on launch. Harmless (cleanup is idempotent, scheduler self-cancels) but
  redundant. `DailyTodo/DailyTodoApp.swift:39-55`. Fix: extract an `activate()` helper to DRY
  the three lines; keep `.task` for cold-launch coverage (onChange doesn't fire for the initial
  value). Low value — verify the launch sequence before changing behavior.

---

## Accessibility (highest-value real gaps; some need a design decision)

- [ ] **Add-task is invisible to VoiceOver (M).** The primary "add" affordance is a
  `Color.clear` button + tap gestures with no labels (`DailyTodo/Views/ListView.swift` ~274,
  303, 57), so a VoiceOver user **cannot add a task from the main screen**. Needs a design
  choice — label the invisible button vs. add a visible toolbar "+"/FAB (which also fixes the
  "no persistent Add button" point below). **Brainstorm before building.**

- [ ] **No persistent Add button (M).** Adding relies entirely on tapping empty space, which
  shrinks/scrolls off as the list fills. A fixed toolbar "+" solves this and the VoiceOver gap
  together. Design decision.

- [ ] **Undo toast a11y (M).** The fixed 5s auto-dismiss ignores VoiceOver and the toast isn't
  announced; since undo is the only delete safety net, this matters.
  `DailyTodo/Views/ListView.swift` (`.task(id: pendingUndo?.id)`), `DailyTodo/Views/UndoToast.swift`.
  Fix: post an accessibility announcement when it appears; pause/extend the auto-dismiss while
  VoiceOver is running.

- [ ] **Secondary-text contrast below WCAG (S, but app-wide visual call).** `appTextSecondary`
  light `#93787B` ≈ 3.6:1 (under 4.5:1), used for empty state, completed titles, timestamps.
  `Shared/Theme.swift:31`. Fix: darken the light value. Changes the app's look — get sign-off.

---

## Live Activity / widget polish (small correctness)

- [ ] **Live Activity `staleDate: nil` (S).** Activities are created/updated with
  `staleDate: nil` everywhere, so when the list empties the activity lingers on "Nothing yet"
  indefinitely. `DailyTodo/LiveActivityController.swift`, `Shared/LiveActivityBridge.swift`.
  Fix: set a sensible `staleDate`, and/or end the activity when the list is empty.

- [ ] **Widget `.never` timeline policy (S).** `TodoProvider.getTimeline` uses `.never`, so if a
  midnight cleanup is missed the widget can show yesterday's tasks until the app reopens.
  `DailyTodoWidgets/TodoListWidget.swift`. Fix: `.after(nextMidnight)` to self-heal.

- [ ] **Live Activity has no "+N more" indicator (S).** The widget shows "+N more" but the Live
  Activity / Dynamic Island silently truncate at `.prefix(3)`. `DailyTodoWidgets/TodoLiveActivity.swift`.
  Fix: add a "+N more" label mirroring the widget when `tasks.count > 3`.

- [ ] **Widget/intent concurrent-save conflict swallowed (M).** `TodoProvider.load()` and
  `ToggleTaskIntent` each make a fresh `ModelContext(TaskStore.shared)`; two near-simultaneous
  toggles can hit a merge conflict that `try?`/`try` discards, losing a toggle.
  `DailyTodoWidgets/TodoListWidget.swift:38`, `Shared/ToggleTaskIntent.swift:25`. Fix: use
  `TaskStore.shared.mainContext` or serialize; at minimum surface the error.

---

## Needs verification before investing

- [ ] **Stale in-app UI after widget/Siri writes (M, verify first).** SwiftData may not surface
  cross-process writes (App Group store) to the app's `@Query`, so the list can show stale state
  after a widget/Siri mutation until it re-foregrounds. Reproduce on-device first — the
  foreground refresh may already mask it. If real: adopt remote-change handling / refresh on
  `.active` (partly already happens).

---

## Bigger / not a quick fix

- [ ] **`fatalError` on container init + no migration plan (M).** `TaskStore.makeContainer`
  `fatalError`s on any store/migration/entitlement failure, crash-looping app + widget.
  `Shared/TaskStore.swift:25`. Fine today, but the first `@Model` change shipped to TestFlight
  will crash existing installs. Add a `VersionedSchema` + migration plan before the next schema
  change, and consider graceful recovery instead of `fatalError`.

---

## Deferred features (explicitly out of scope — not bugs)

- Control Center / Action-button widget (`ControlWidget`, reuses `AddTaskIntent`).
- `?title=` deep link + parameterized Siri phrases ("Complete X", "Add X").
- Donate intents for Siri/Spotlight prediction.
- DST/timezone edge cases in `MidnightScheduler`/`DailyCleanup` (mitigated by foreground catch-up; very low real-world impact).
