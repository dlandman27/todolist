# Persistent Add Button (FAB) — Design

**Date:** 2026-06-28
**Status:** Approved

## Problem

Adding a task currently relies entirely on tapping empty space — the `Color.clear`
button below the rows (`ListView.list`) and the empty-state tap gesture
(`ListView.emptyState`). This has two real consequences, both flagged in
`techdebt.md`:

1. **Invisible to VoiceOver.** The add affordance is an unlabeled `Color.clear`
   button + tap gestures, so a VoiceOver user **cannot add a task from the main
   screen** at all.
2. **Undiscoverable / shrinking target.** Tap-to-add space scrolls off and
   shrinks as the list fills, and a first-time user has no visible "add" cue
   beyond the empty-state hint text.

## Goal

Add a single, always-visible, accessible Add button that makes the app's primary
action obvious and reachable — without disturbing the existing minimalist layout
or the date-free, single-list philosophy.

## Non-goals

- No settings/toggle to hide it. The primary action is not optional; a toggle
  would be bloat and would leave VoiceOver users stuck if defaulted off. Always
  shown.
- No new model, store, persistence, or migration changes.
- No removal of the existing tap-to-add gestures — the FAB is purely additive.

## Design

### Placement & layout

A circular "+" button (FAB) pinned to the **bottom-right**, living in the same
bottom `safeAreaInset(edge: .bottom)` as the existing Go Live control.

The inset's content becomes a `ZStack`:

- **Go Live** control stays centered, unchanged.
- **FAB** aligns `.bottomTrailing`.

This keeps the FAB above the home indicator and riding above the keyboard,
consistent with how the Go Live control already behaves. The undo toast continues
to slide in above the whole cluster (it remains in the `VStack` above the Go Live
control; the FAB sits in the trailing corner and does not overlap the centered
toast).

### Style

- Solid `Color.brand`-filled circle, ~56pt diameter.
- White `plus` SF Symbol, weight `.semibold`, centered.
- A subtle shadow to lift it off the list background.
- Deliberately a **solid fill** rather than the app's glass capsules, so the
  primary action reads as primary and stands out from list chrome.

### Behavior

- Tapping calls the **existing `addTask()`** — no new logic. It inherits the
  current behavior:
  - If a blank Today draft already exists, focus it instead of stacking another
    row.
  - Otherwise insert a new row (via `TaskActions.add`) and drop the cursor into
    it.
  - Light haptic on add (already inside `addTask()`).
- Existing tap-on-empty-space (`list`) and empty-state tap (`emptyState`)
  gestures are unchanged.

### Always visible

Shown in **both** the populated list and the empty state, and regardless of the
Live Activities on/off branch (`live.systemEnabled`). The FAB lives in the bottom
inset, which is always present, so it does not depend on which body branch is
rendered.

### Accessibility

- `.accessibilityLabel("Add task")`.
- `.accessibilityIdentifier("addTask")` so a UI test can assert it.
- This is the core motivation: a VoiceOver user can now add a task from the main
  screen.

## Files touched

- `DailyTodo/Views/ListView.swift` — wrap the bottom inset content in a `ZStack`
  and add the FAB view (a new private `addButton` computed property). View-only
  change.
- `DailyTodoUITests/TaskFlowUITests.swift` — add a test that taps the FAB by its
  accessibility identifier and confirms a new editable row appears.

## Testing

- **UI test:** launch, tap the `addButton`, assert a new task row / focused field
  appears. Covers the accessibility identifier and the wired-up action.
- **Manual:** verify the FAB shows in empty state and populated list; verify it
  rides above the keyboard while editing; verify VoiceOver reads "Add task" and
  activating it adds a row; verify it doesn't overlap the undo toast or Go Live.

## Risks

Minimal — view-only, no persistence/model changes. The only layout risk is
crowding between the FAB and the centered Go Live control on small screens;
mitigated by the trailing alignment and the toast remaining centered above.
