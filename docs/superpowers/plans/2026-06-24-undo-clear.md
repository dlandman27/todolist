# Undo for Clear Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user undo "Clear Completed" and "Clear All" via a transient bottom toast that restores the removed tasks exactly as they were.

**Architecture:** `TaskActions.clearCompleted`/`clearAll` capture lightweight value snapshots of the tasks they delete and return them; a new `TaskActions.restore` re-inserts those snapshots preserving identity and order. `ListView` holds the most-recent batch in transient `@State`, shows an `UndoToast` above the Go-Live pill, and auto-dismisses after ~5s. No persistence, no schema change.

**Tech Stack:** Swift, SwiftUI, SwiftData, ActivityKit, XCTest. Xcode project `DailyTodo.xcodeproj`, test scheme `DailyTodo`.

## Global Constraints

- Undo scope is **Clear Completed** and **Clear All** only. Swipe-delete and `DailyCleanup` (midnight) are unchanged and show no toast.
- Undo is **in-memory** and dies when the toast hides (~5s) or the app backgrounds. No on-disk persistence.
- Restore must preserve each task's original `id`, `title`, `done`, `createdAt`, `completedAt`, and `sortOrder`.
- Reuse existing tokens: `Animation.appMotion`, `Color.appSurface`, `Color.brand`, `Color.textPrimary`, `Color.textSecondary`. Side-effects after any list mutation: `live.refresh()` + `WidgetCenter.shared.reloadAllTimelines()`.
- `clearCompleted`/`clearAll` stay `@discardableResult`.

## File Structure

- `Shared/TaskActions.swift` — add `TaskSnapshot`, change two return types, add `restore`.
- `DailyTodoTests/TaskActionsTests.swift` — update 4 existing assertions, add 2 round-trip tests.
- `DailyTodo/Siri/TaskIntents.swift` — keep `ClearCompletedIntent` compiling against the new return type.
- `DailyTodo/Views/UndoToast.swift` — **new** presentational toast view.
- `DailyTodo/Views/ListView.swift` — undo state, wiring, placement, dialog wording.

To run tests (substitute an installed simulator if `iPhone 16` is absent — list with `xcrun simctl list devices available`):

```bash
xcodebuild test -scheme DailyTodo -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:DailyTodoTests/TaskActionsTests
```

---

### Task 1: Snapshots + restore in `TaskActions`

**Files:**
- Modify: `Shared/TaskActions.swift`
- Modify: `DailyTodo/Siri/TaskIntents.swift:96`
- Test: `DailyTodoTests/TaskActionsTests.swift`

**Interfaces:**
- Produces:
  - `struct TaskSnapshot { let id: UUID; let title: String; let done: Bool; let createdAt: Date; let completedAt: Date?; let sortOrder: Int; init(_ task: TaskItem) }`
  - `TaskActions.clearCompleted(in: ModelContext) -> [TaskSnapshot]` (was `-> Int`)
  - `TaskActions.clearAll(in: ModelContext) -> [TaskSnapshot]` (was `-> Int`)
  - `TaskActions.restore(_ snapshots: [TaskSnapshot], in: ModelContext)`

- [ ] **Step 1: Update existing tests + add round-trip tests**

In `DailyTodoTests/TaskActionsTests.swift`, change the four count assertions to read `.count`:

```swift
// testClearCompletedRemovesOnlyDoneTasks
XCTAssertEqual(removed.count, 1)
// testClearCompletedWithNoneDoneRemovesNothing
XCTAssertEqual(removed.count, 0)
// testClearAllEmptiesTheStore
XCTAssertEqual(removed.count, 2)
// testClearAllOnEmptyStoreReturnsZero
XCTAssertEqual(removed.count, 0)
```

Then add two new tests (place after `testClearAllOnEmptyStoreReturnsZero`):

```swift
func testClearCompletedReturnsSnapshotsOfRemovedTasks() throws {
    let context = try makeContext()
    let open = TaskItem(title: "Open")
    let done = TaskItem(title: "Done", done: true,
                        completedAt: Date(timeIntervalSince1970: 50), sortOrder: 2)
    context.insert(open)
    context.insert(done)
    try context.save()

    let snaps = TaskActions.clearCompleted(in: context)

    XCTAssertEqual(snaps.map(\.title), ["Done"])
    XCTAssertEqual(snaps.first?.id, done.id)
    XCTAssertEqual(snaps.first?.sortOrder, 2)
    XCTAssertEqual(snaps.first?.completedAt, Date(timeIntervalSince1970: 50))
}

func testRestoreReinsertsTasksWithIdentityOrderAndDoneState() throws {
    let context = try makeContext()
    let a = TaskItem(title: "A", sortOrder: 0)
    let b = TaskItem(title: "B", done: true,
                     completedAt: Date(timeIntervalSince1970: 99), sortOrder: 1)
    context.insert(a)
    context.insert(b)
    try context.save()
    let originalOrder = TaskOrdering.ordered(context.allTasks()).map(\.id)

    let snaps = TaskActions.clearAll(in: context)
    XCTAssertTrue(context.allTasks().isEmpty)

    TaskActions.restore(snaps, in: context)

    XCTAssertEqual(context.allTasks().count, 2)
    let byId = Dictionary(uniqueKeysWithValues: context.allTasks().map { ($0.id, $0) })
    XCTAssertEqual(byId[b.id]?.done, true)
    XCTAssertEqual(byId[b.id]?.completedAt, Date(timeIntervalSince1970: 99))
    XCTAssertEqual(byId[b.id]?.sortOrder, 1)
    XCTAssertEqual(TaskOrdering.ordered(context.allTasks()).map(\.id), originalOrder)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -scheme DailyTodo -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:DailyTodoTests/TaskActionsTests
```
Expected: FAIL — compile errors (`TaskSnapshot`/`restore` undefined; `[TaskSnapshot]` vs `Int`). A compile failure of the test target counts as red.

- [ ] **Step 3: Implement snapshot, new return types, and restore**

In `Shared/TaskActions.swift`, add the snapshot type at the top of the `enum TaskActions` body (or just above it in the file):

```swift
/// A snapshot of a task's restorable state, captured before a bulk delete so the
/// action can be undone. Holds plain values (no SwiftData identity) so it outlives
/// the deleted object.
struct TaskSnapshot {
    let id: UUID
    let title: String
    let done: Bool
    let createdAt: Date
    let completedAt: Date?
    let sortOrder: Int

    init(_ task: TaskItem) {
        id = task.id
        title = task.title
        done = task.done
        createdAt = task.createdAt
        completedAt = task.completedAt
        sortOrder = task.sortOrder
    }
}
```

Replace `clearCompleted` and `clearAll` with snapshot-returning versions:

```swift
/// Delete all completed tasks. Returns snapshots of what was removed (for undo).
@discardableResult
static func clearCompleted(in context: ModelContext) -> [TaskSnapshot] {
    let completed = context.allTasks().filter { $0.done }
    let snapshots = completed.map(TaskSnapshot.init)
    for task in completed { context.delete(task) }
    try? context.save()
    return snapshots
}

/// Delete every task. Returns snapshots of what was removed (for undo).
@discardableResult
static func clearAll(in context: ModelContext) -> [TaskSnapshot] {
    let all = context.allTasks()
    let snapshots = all.map(TaskSnapshot.init)
    for task in all { context.delete(task) }
    try? context.save()
    return snapshots
}

/// Re-insert tasks captured by `clearCompleted`/`clearAll`, preserving their original
/// id, order, and completion state so the list returns exactly as it was.
static func restore(_ snapshots: [TaskSnapshot], in context: ModelContext) {
    for snap in snapshots {
        context.insert(
            TaskItem(
                id: snap.id,
                title: snap.title,
                done: snap.done,
                createdAt: snap.createdAt,
                completedAt: snap.completedAt,
                sortOrder: snap.sortOrder
            )
        )
    }
    try? context.save()
}
```

In `DailyTodo/Siri/TaskIntents.swift`, keep `ClearCompletedIntent` working with an `Int` by taking `.count` (line 96):

```swift
let removed = TaskActions.clearCompleted(in: context).count
```

(`ClearAllIntent` at line 123 ignores the return via `@discardableResult` — leave it unchanged.)

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodebuild test -scheme DailyTodo -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:DailyTodoTests/TaskActionsTests
```
Expected: PASS — all `TaskActionsTests` green.

- [ ] **Step 5: Commit**

```bash
git add Shared/TaskActions.swift DailyTodo/Siri/TaskIntents.swift DailyTodoTests/TaskActionsTests.swift
git commit -m "Add task snapshots and restore to TaskActions"
```

---

### Task 2: `UndoToast` view

**Files:**
- Create: `DailyTodo/Views/UndoToast.swift`

**Interfaces:**
- Produces: `UndoToast(message: String, onUndo: () -> Void)` — a presentational view; timing/dismissal is owned by the caller.

- [ ] **Step 1: Create the toast view**

Create `DailyTodo/Views/UndoToast.swift`:

```swift
import SwiftUI

/// Transient bottom toast shown after a bulk clear, offering a one-tap Undo.
/// Purely presentational — the caller owns when it appears and auto-dismisses.
struct UndoToast: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.textPrimary)
            Spacer(minLength: 12)
            Button(action: onUndo) {
                Text("Undo")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.brand)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 18)
        .background(
            Capsule()
                .fill(Color.appSurface)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        )
        .padding(.horizontal)
    }
}

#Preview {
    UndoToast(message: "Cleared 5 tasks", onUndo: {})
}
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
xcodebuild build -scheme DailyTodo -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add DailyTodo/Views/UndoToast.swift
git commit -m "Add UndoToast view"
```

---

### Task 3: Wire undo into `ListView` + fix dialog wording

**Files:**
- Modify: `DailyTodo/Views/ListView.swift`

**Interfaces:**
- Consumes: `TaskActions.clearCompleted`/`clearAll` (return `[TaskSnapshot]`), `TaskActions.restore`, `UndoToast(message:onUndo:)`.

- [ ] **Step 1: Add undo state and scene phase**

In `ListView`, add alongside the existing `@State` declarations (near the top, after `@State private var showClearCompletedConfirm = false`):

```swift
@State private var pendingClear: PendingClear?
@Environment(\.scenePhase) private var scenePhase

/// The most recently cleared batch, held in memory only while the undo toast is up.
private struct PendingClear {
    let id = UUID()
    let snapshots: [TaskSnapshot]
    let message: String
}
```

- [ ] **Step 2: Capture snapshots on clear, add undo + present helpers**

Replace the existing `clearCompleted()` and `clearAll()` (currently at ~line 322-336) with:

```swift
/// Remove all completed tasks immediately (low-risk; only done items), then offer undo.
private func clearCompleted() {
    var removed: [TaskSnapshot] = []
    withAnimation(.appMotion) { removed = TaskActions.clearCompleted(in: context) }
    Haptics.notify(.warning)
    live.refresh()
    WidgetCenter.shared.reloadAllTimelines()
    presentUndo(for: removed)
}

/// Remove every task (confirmed via dialog before this runs), then offer undo.
private func clearAll() {
    var removed: [TaskSnapshot] = []
    withAnimation(.appMotion) { removed = TaskActions.clearAll(in: context) }
    Haptics.notify(.warning)
    live.refresh()
    WidgetCenter.shared.reloadAllTimelines()
    presentUndo(for: removed)
}

/// Surface the undo toast for a just-cleared batch. No-op if nothing was removed.
private func presentUndo(for snapshots: [TaskSnapshot]) {
    guard !snapshots.isEmpty else { return }
    let count = snapshots.count
    pendingClear = PendingClear(
        snapshots: snapshots,
        message: "Cleared \(count) task\(count == 1 ? "" : "s")"
    )
}

/// Restore the most recently cleared batch and dismiss the toast.
private func undoClear() {
    guard let pending = pendingClear else { return }
    withAnimation(.appMotion) { TaskActions.restore(pending.snapshots, in: context) }
    Haptics.selection()
    live.refresh()
    WidgetCenter.shared.reloadAllTimelines()
    pendingClear = nil
}
```

- [ ] **Step 3: Place the toast above the Go-Live pill**

Replace the existing bottom inset (currently `.safeAreaInset(edge: .bottom) { liveActivityButton }` at ~line 61) with:

```swift
.safeAreaInset(edge: .bottom) {
    VStack(spacing: 10) {
        if let pending = pendingClear {
            UndoToast(message: pending.message, onUndo: undoClear)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        liveActivityButton
    }
    .animation(.appMotion, value: pendingClear?.id)
}
```

- [ ] **Step 4: Auto-dismiss after ~5s and on background**

Add these modifiers next to the existing `.onChange(of: router.addRequested)` on the `NavigationStack` (just after it):

```swift
.task(id: pendingClear?.id) {
    guard pendingClear != nil else { return }
    try? await Task.sleep(for: .seconds(5))
    guard !Task.isCancelled else { return }
    withAnimation(.appMotion) { pendingClear = nil }
}
.onChange(of: scenePhase) { _, phase in
    if phase == .background { pendingClear = nil }
}
```

- [ ] **Step 5: Fix the confirmation dialog wording**

Both clear dialogs currently end with `Text("This can't be undone.")` (lines ~71 and ~81). Replace **both** occurrences with:

```swift
Text("You can undo this right after.")
```

- [ ] **Step 6: Build**

Run:
```bash
xcodebuild build -scheme DailyTodo -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Manual verification in the simulator**

Launch the app and confirm:
1. Add several tasks, complete some. ⋯ menu → **Clear Completed** → a toast "Cleared N task(s)" slides up above the Go-Live pill; tap **Undo** → the completed tasks return in their original (sunk) positions, still checked.
2. ⋯ menu → **Clear All** → confirmation dialog reads "You can undo this right after." → confirm → toast appears; wait ~5s → toast auto-hides and the list stays empty.
3. Clear, then Clear again quickly → the second toast replaces the first (only the latest batch is restorable).
4. Clear, send the app to background, reopen → no stale toast is shown.
5. Undo a Clear All while the Live Activity is running → the Lock Screen activity reflects the restored tasks.

- [ ] **Step 8: Commit**

```bash
git add DailyTodo/Views/ListView.swift
git commit -m "Add undo toast for Clear Completed and Clear All"
```

---

## Self-Review

**Spec coverage:**
- Scope (Clear Completed + Clear All only) → Tasks 1 & 3; midnight/swipe untouched (verified: only `ClearCompletedIntent` and `ListView` consume the return; `DailyCleanup` and `ClearAllIntent` discard it). ✓
- Toast UI with Undo button → Task 2 + Task 3 Step 3. ✓
- In-memory, dies with toast (~5s) + background → Task 3 Step 4. ✓
- Keep both dialogs, fix wording → Task 3 Step 5. ✓
- Snapshot + re-insert (Approach A), preserve id/order/done → Task 1 (`TaskSnapshot`, `restore`) + round-trip test. ✓
- Side-effects (`live.refresh()` + widget reload) on clear and undo → Task 3 Steps 2. ✓
- Tests (snapshot return, round-trip, ordering) → Task 1 Step 1. ✓

**Placeholder scan:** No TBD/TODO; all code blocks complete. ✓

**Type consistency:** `TaskSnapshot` fields and `init(_:)`, `clearCompleted`/`clearAll` → `[TaskSnapshot]`, `restore(_:in:)`, `PendingClear`, `UndoToast(message:onUndo:)`, `pendingClear` used consistently across Tasks 1–3. `TaskItem` init already accepts `id/title/done/createdAt/completedAt/sortOrder`. ✓
