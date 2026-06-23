# Clear Tasks (Mass Deletion) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add manual bulk deletion — Clear Completed and Clear All — via a new ⋯ list-options menu in the header, backed by a reusable `TaskActions` util.

**Architecture:** A pure `TaskActions` enum in `Shared/` performs the deletions on a `ModelContext` and returns the count removed; the view layer triggers them from a sectioned `Menu`, animates with the shared spring, fires a haptic, and refreshes the Live Activity + widgets. Clear All is guarded by a confirmation dialog.

**Tech Stack:** SwiftUI, SwiftData, XcodeGen, XCTest. iOS 17 deployment target.

## Global Constraints

- iOS deployment target: **17.0**. Use only APIs available on iOS 17.
- This is an **XcodeGen** project: after adding/removing any source file, run `xcodegen generate` before building (sources are listed at generation time).
- New files in `Shared/` are compiled into both the app and the widget extension; keep them free of app-only APIs.
- After any task mutation, refresh the other surfaces: `LiveActivityController.shared.refresh()` and `WidgetCenter.shared.reloadAllTimelines()`.
- All deletions animate with `withAnimation(.appMotion)` (existing shared spring in `Shared/Theme.swift`).
- Haptics go through the existing gated `Haptics` util; use `Haptics.notify(.warning)` for deletions.
- No undo. No sorting (the ⋯ menu is only *structured* to host a future Sort section).
- Simulator for builds/tests: iPhone 17 Pro Max (booted). Destination string: `platform=iOS Simulator,name=iPhone 17 Pro Max`.

---

### Task 1: `TaskActions` deletion util

**Files:**
- Create: `Shared/TaskActions.swift`
- Create: `DailyTodoTests/TaskActionsTests.swift`

**Interfaces:**
- Consumes: `ModelContext.allTasks()` (from `Shared/TaskStore.swift`), `TaskItem` (from `Shared/TaskItem.swift`).
- Produces:
  - `TaskActions.clearCompleted(in context: ModelContext) -> Int` — deletes all tasks with `done == true`, saves, returns count removed.
  - `TaskActions.clearAll(in context: ModelContext) -> Int` — deletes all tasks, saves, returns count removed.

- [ ] **Step 1: Write the failing tests**

Create `DailyTodoTests/TaskActionsTests.swift`:

```swift
import XCTest
import SwiftData
@testable import DailyTodo

final class TaskActionsTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: TaskItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    func testClearCompletedRemovesOnlyDoneTasks() throws {
        let context = try makeContext()
        let open = TaskItem(title: "Open")
        let done = TaskItem(title: "Done", done: true)
        context.insert(open)
        context.insert(done)
        try context.save()

        let removed = TaskActions.clearCompleted(in: context)

        XCTAssertEqual(removed, 1)
        XCTAssertEqual(context.allTasks().map(\.title), ["Open"])
    }

    func testClearCompletedWithNoneDoneRemovesNothing() throws {
        let context = try makeContext()
        context.insert(TaskItem(title: "Open"))
        try context.save()

        let removed = TaskActions.clearCompleted(in: context)

        XCTAssertEqual(removed, 0)
        XCTAssertEqual(context.allTasks().count, 1)
    }

    func testClearAllEmptiesTheStore() throws {
        let context = try makeContext()
        context.insert(TaskItem(title: "A"))
        context.insert(TaskItem(title: "B", done: true))
        try context.save()

        let removed = TaskActions.clearAll(in: context)

        XCTAssertEqual(removed, 2)
        XCTAssertTrue(context.allTasks().isEmpty)
    }

    func testClearAllOnEmptyStoreReturnsZero() throws {
        let context = try makeContext()

        let removed = TaskActions.clearAll(in: context)

        XCTAssertEqual(removed, 0)
    }
}
```

- [ ] **Step 2: Regenerate the project so the new test file is in the target**

Run: `xcodegen generate`
Expected: `Created project at .../DailyTodo.xcodeproj`

- [ ] **Step 3: Run the tests to verify they fail**

Run:
```bash
xcodebuild test -project DailyTodo.xcodeproj -scheme DailyTodo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:DailyTodoTests/TaskActionsTests 2>&1 | tail -20
```
Expected: compile failure — `cannot find 'TaskActions' in scope`.

- [ ] **Step 4: Write the implementation**

Create `Shared/TaskActions.swift`:

```swift
import SwiftData

/// Bulk deletion operations on the list, shared between the manual clear menu and
/// the upcoming midnight auto-delete. Pure data mutation — callers are responsible
/// for any Live Activity / widget refresh afterward.
enum TaskActions {
    /// Delete all completed tasks. Returns the number removed.
    @discardableResult
    static func clearCompleted(in context: ModelContext) -> Int {
        let completed = context.allTasks().filter { $0.done }
        for task in completed { context.delete(task) }
        try? context.save()
        return completed.count
    }

    /// Delete every task. Returns the number removed.
    @discardableResult
    static func clearAll(in context: ModelContext) -> Int {
        let all = context.allTasks()
        for task in all { context.delete(task) }
        try? context.save()
        return all.count
    }
}
```

- [ ] **Step 5: Regenerate the project so the new source file is in the target**

Run: `xcodegen generate`
Expected: `Created project at .../DailyTodo.xcodeproj`

- [ ] **Step 6: Run the tests to verify they pass**

Run:
```bash
xcodebuild test -project DailyTodo.xcodeproj -scheme DailyTodo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:DailyTodoTests/TaskActionsTests 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`, 4 tests passing.

- [ ] **Step 7: Commit**

```bash
git add Shared/TaskActions.swift DailyTodoTests/TaskActionsTests.swift project.yml DailyTodo.xcodeproj
git commit -m "feat: add TaskActions util for bulk task deletion"
```

---

### Task 2: ⋯ list-options menu with Clear Completed / Clear All

**Files:**
- Modify: `DailyTodo/Views/ListView.swift`

**Interfaces:**
- Consumes: `TaskActions.clearCompleted(in:)`, `TaskActions.clearAll(in:)` (Task 1); `Animation.appMotion`, `Haptics.notify(_:)`, `Color.brand` (existing); `live` (`LiveActivityController`) and `context` (`modelContext`) already present in `ListView`.
- Produces: no new public interface (view-internal UI).

- [ ] **Step 1: Add the confirmation-dialog state**

In `ListView`, add this stored property next to the other `@State`/`@FocusState` declarations (just below `@FocusState private var titleFocused: Bool`):

```swift
@State private var showClearAllConfirm = false
```

- [ ] **Step 2: Add a helper to know whether any task is completed**

In `ListView`, add next to the existing `isEditing` computed property:

```swift
/// Whether any task is checked off — gates the "Clear Completed" menu item.
private var hasCompletedTasks: Bool { tasks.contains { $0.done } }
```

- [ ] **Step 3: Add the list-options menu button**

In `ListView`, add this computed property next to `settingsButton`:

```swift
/// The ⋯ list-options menu: bulk actions on this list. Sections keep room for a
/// future "Sort By" section without adding another header button.
private var listOptionsButton: some View {
    Menu {
        Section {
            Button {
                clearCompleted()
            } label: {
                Label("Clear Completed", systemImage: "checkmark.circle")
            }
            .disabled(!hasCompletedTasks)

            Button(role: .destructive) {
                showClearAllConfirm = true
            } label: {
                Label("Clear All", systemImage: "trash")
            }
            .disabled(tasks.isEmpty)
        }
    } label: {
        Image(systemName: "ellipsis.circle")
            .font(.title2)
            .foregroundStyle(Color.brand)
    }
    .accessibilityIdentifier("listOptions")
    .accessibilityLabel("List options")
}
```

- [ ] **Step 4: Place the menu button left of the gear in the header**

In `titleHeader`, change the trailing controls from:

```swift
            Spacer()
            settingsButton
        }
```

to:

```swift
            Spacer()
            listOptionsButton
            settingsButton
        }
```

- [ ] **Step 5: Add the clear action functions**

In `ListView`, add these methods next to `delete(_:)`:

```swift
/// Remove all completed tasks immediately (low-risk; only done items).
private func clearCompleted() {
    withAnimation(.appMotion) { TaskActions.clearCompleted(in: context) }
    Haptics.notify(.warning)
    live.refresh()
    WidgetCenter.shared.reloadAllTimelines()
}

/// Remove every task (confirmed via dialog before this runs).
private func clearAll() {
    withAnimation(.appMotion) { TaskActions.clearAll(in: context) }
    Haptics.notify(.warning)
    live.refresh()
    WidgetCenter.shared.reloadAllTimelines()
}
```

- [ ] **Step 6: Attach the Clear All confirmation dialog**

In `body`, attach a confirmation dialog to the `ZStack` inside the `NavigationStack`. Change:

```swift
            .safeAreaInset(edge: .bottom) { liveActivityButton }
            .toolbar(.hidden, for: .navigationBar)
        }
```

to:

```swift
            .safeAreaInset(edge: .bottom) { liveActivityButton }
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog(
                "Delete all \(tasks.count) tasks?",
                isPresented: $showClearAllConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete All", role: .destructive) { clearAll() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
        }
```

- [ ] **Step 7: Build**

Run:
```bash
xcodebuild -project DailyTodo.xcodeproj -scheme DailyTodo -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -derivedDataPath ./build build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Install, launch, and verify manually**

Run:
```bash
DEVICE=$(xcrun simctl list devices booted | grep -o '[0-9A-F-]\{36\}' | head -1)
xcrun simctl install "$DEVICE" ./build/Build/Products/Debug-iphonesimulator/DailyTodo.app
xcrun simctl launch "$DEVICE" com.dylanlandman.dailytodo
```
Manually verify in the simulator:
- The ⋯ button appears left of the gear.
- With no completed tasks, "Clear Completed" is greyed out; with completed tasks it is enabled and removes only the completed ones (open tasks remain), animated.
- With an empty list, "Clear All" is greyed out; otherwise it shows the confirmation dialog. Cancel aborts; Delete All empties the list, animated.

- [ ] **Step 9: Commit**

```bash
git add DailyTodo/Views/ListView.swift
git commit -m "feat: add list-options menu with Clear Completed and Clear All"
```

---

## Self-Review

- **Spec coverage:**
  - `TaskActions` util (clearCompleted/clearAll, returns count, caller handles refresh) → Task 1. ✓
  - ⋯ menu left of gear, sectioned → Task 2 Steps 3–4. ✓
  - Smart enablement (disable no-ops) → Task 2 Step 3 (`.disabled`). ✓
  - Confirm Clear All only; Clear Completed immediate → Task 2 Steps 5–6. ✓
  - Feedback: appMotion + Haptics.notify(.warning) → Task 2 Step 5. ✓
  - Refresh LA + widgets after delete → Task 2 Step 5. ✓
  - `TaskActions` unit tests (4 cases) → Task 1 Step 1. ✓
  - Reuse note for Issue 1 → satisfied by `TaskActions` being a shared util; no code needed now. ✓
- **Placeholder scan:** none — all steps contain concrete code/commands.
- **Type consistency:** `clearCompleted(in:)`/`clearAll(in:)` names and `-> Int` signatures match between Task 1 (definition) and Task 2 (calls). `hasCompletedTasks`, `showClearAllConfirm`, `listOptionsButton`, `clearCompleted()`, `clearAll()` referenced consistently within Task 2.
