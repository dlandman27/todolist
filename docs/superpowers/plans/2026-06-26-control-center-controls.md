# Control Center Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three iOS 18+ Control Center controls to 1List — Quick Add, Tasks Left, and Stashed — each acting on the existing shared task store.

**Architecture:** Controls are `ControlWidget`s added to the existing `DailyTodoWidgets` app-extension bundle, gated `@available(iOS 18.0, *)`. They read counts from the shared SwiftData store via a pure `ControlCounts` helper, open the app through deep links (`dailytodo://add`, `dailytodo://stash`) or an app-opening intent, and refresh through a single `Surfaces.reload()` entry point that fans out to both WidgetKit and ControlKit.

**Tech Stack:** Swift, SwiftUI, WidgetKit (Controls API), AppIntents, SwiftData, XCTest. XcodeGen (`project.yml`) for the project; `xcodebuild` for builds/tests.

## Global Constraints

- App deployment target stays **iOS 17.0** (`project.yml`). All control code is gated `@available(iOS 18.0, *)` and registered behind `if #available(iOS 18.0, *)`.
- Controls live in the existing **`DailyTodoWidgets`** target; shared logic lives in **`Shared/`** (compiled into both app and extension).
- Read the store via `ModelContext(TaskStore.shared)` — never construct a new container.
- Display name in user-facing copy is **"1List"** / list title from `ListSettings.name` where relevant.
- Build/test command (from `AGENTS.md`):
  `xcodebuild -scheme DailyTodo -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath build <build|test>`
- After editing `project.yml` (only if a target's source globs change), regenerate with `xcodegen`. Adding files under already-globbed folders (`Shared/`, `DailyTodoWidgets/`, `DailyTodoTests/`) needs **no** project.yml change.

---

### Task 1: `ControlCounts` count helper

Pure functions the control value providers wrap, so the counting logic is unit-testable without iOS 18 / WidgetKit.

**Files:**
- Create: `Shared/ControlCounts.swift`
- Test: `DailyTodoTests/ControlCountsTests.swift`

**Interfaces:**
- Consumes: `ModelContext.orderedTasks()` and `ModelContext.stashedTasks()` (existing, in `Shared/TaskStore.swift`).
- Produces:
  - `ControlCounts.open(in: ModelContext) -> Int` — open (not done) tasks in Today.
  - `ControlCounts.stashed(in: ModelContext) -> Int` — tasks in the stash.

- [ ] **Step 1: Write the failing test**

Create `DailyTodoTests/ControlCountsTests.swift`:

```swift
import XCTest
import SwiftData
@testable import DailyTodo

final class ControlCountsTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: TaskItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    func testOpenCountsOnlyOpenTodayTasks() throws {
        let context = try makeContext()
        context.insert(TaskItem(title: "Open one"))
        context.insert(TaskItem(title: "Open two"))
        context.insert(TaskItem(title: "Done", done: true))
        context.insert(TaskItem(title: "Stashed", isStashed: true))
        context.insert(TaskItem(title: ""))            // blank draft — excluded
        try context.save()

        XCTAssertEqual(ControlCounts.open(in: context), 2)
    }

    func testStashedCountsOnlyStashedTasks() throws {
        let context = try makeContext()
        context.insert(TaskItem(title: "Open"))
        context.insert(TaskItem(title: "Stash one", isStashed: true))
        context.insert(TaskItem(title: "Stash two", isStashed: true))
        try context.save()

        XCTAssertEqual(ControlCounts.stashed(in: context), 2)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -scheme DailyTodo -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath build -only-testing:DailyTodoTests/ControlCountsTests
```
Expected: FAIL to compile — "cannot find 'ControlCounts' in scope".

- [ ] **Step 3: Write minimal implementation**

Create `Shared/ControlCounts.swift`:

```swift
import Foundation
import SwiftData

/// Counts surfaced by the Control Center controls. Pure wrappers over the store's
/// display helpers so the counting rules stay testable without WidgetKit.
enum ControlCounts {
    /// Open (not done) tasks in Today. Excludes done, stashed, and blank drafts —
    /// `orderedTasks()` already drops the latter two.
    static func open(in context: ModelContext) -> Int {
        context.orderedTasks().filter { !$0.done }.count
    }

    /// Tasks tucked in the stash drawer.
    static func stashed(in context: ModelContext) -> Int {
        context.stashedTasks().count
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
xcodebuild test -scheme DailyTodo -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath build -only-testing:DailyTodoTests/ControlCountsTests
```
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Shared/ControlCounts.swift DailyTodoTests/ControlCountsTests.swift
git commit -m "Add ControlCounts helper for Control Center controls"
```

---

### Task 2: Stash deep link + routing

Add a `dailytodo://stash` deep link that opens the stash drawer, mirroring the existing `dailytodo://add` flow.

**Files:**
- Modify: `Shared/AppGroup.swift` (the `DeepLink` enum, ~lines 41-46)
- Modify: `DailyTodo/DailyTodoApp.swift` (`Router` class ~line 70; `.onOpenURL` ~lines 33-37)
- Modify: `DailyTodo/Views/ListView.swift` (add `.onChange` after the `addRequested` handler at lines 144-149)

**Interfaces:**
- Produces:
  - `DeepLink.stashHost: String` = `"stash"`, `DeepLink.stashURL: URL` = `dailytodo://stash`.
  - `Router.stashRequested: Bool`.
- Consumes: existing `ListView` `@State private var showStash` (line 18) to present `StashSheet` (sheet at lines 159-162).

- [ ] **Step 1: Add the stash deep link**

In `Shared/AppGroup.swift`, replace the `DeepLink` enum body so it reads:

```swift
/// The custom URL scheme used to deep-link into the app (e.g. from the widget's add
/// button or a Control Center control).
enum DeepLink {
    static let scheme = "dailytodo"
    static let addHost = "add"
    static let addURL = URL(string: "\(scheme)://\(addHost)")!
    static let stashHost = "stash"
    static let stashURL = URL(string: "\(scheme)://\(stashHost)")!
}
```

- [ ] **Step 2: Add the router flag**

In `DailyTodo/DailyTodoApp.swift`, update the `Router` class:

```swift
/// Signals an add or stash request (e.g. from a deep link / Control Center control)
/// for the list to act on.
@Observable
final class Router {
    var addRequested = false
    var stashRequested = false
}
```

- [ ] **Step 3: Route the new host on open**

In `DailyTodo/DailyTodoApp.swift`, replace the `.onOpenURL` modifier:

```swift
                .onOpenURL { url in
                    guard url.scheme == DeepLink.scheme else { return }
                    switch url.host {
                    case DeepLink.addHost: router.addRequested = true
                    case DeepLink.stashHost: router.stashRequested = true
                    default: break
                    }
                }
```

- [ ] **Step 4: Open the stash drawer when requested**

In `DailyTodo/Views/ListView.swift`, immediately after the existing `addRequested` handler (the block ending at line 149), add:

```swift
        .onChange(of: router.stashRequested) { _, requested in
            if requested {
                showStash = true
                router.stashRequested = false
            }
        }
```

- [ ] **Step 5: Build to verify it compiles**

Run:
```bash
xcodebuild -scheme DailyTodo -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath build build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Manually verify the deep link (optional but recommended)**

```bash
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/DailyTodo.app
xcrun simctl launch booted com.dylanlandman.dailytodo
xcrun simctl openurl booted "dailytodo://stash"
xcrun simctl io booted screenshot /tmp/stash-deeplink.png
```
Expected: the stash drawer (`StashSheet`) is presented. Then verify add still works:
```bash
xcrun simctl openurl booted "dailytodo://add"
```
Expected: a new editable task row appears.

- [ ] **Step 7: Commit**

```bash
git add Shared/AppGroup.swift DailyTodo/DailyTodoApp.swift DailyTodo/Views/ListView.swift
git commit -m "Add dailytodo://stash deep link to open the stash drawer"
```

---

### Task 3: The three controls + bundle registration

Create the controls and register them in the widget bundle. This also introduces `Surfaces` (the reload entry point) because the controls' kind strings live there; the actual reload wiring happens in Task 4.

**Files:**
- Create: `Shared/Surfaces.swift`
- Create: `DailyTodoWidgets/TodoControls.swift`
- Modify: `DailyTodoWidgets/DailyTodoWidgetsBundle.swift`

**Interfaces:**
- Consumes: `ControlCounts.open(in:)`, `ControlCounts.stashed(in:)` (Task 1); `DeepLink.addURL`, `DeepLink.stashURL` (Task 2); `TaskStore.shared`.
- Produces:
  - `ControlKind.quickAdd`, `ControlKind.tasksLeft`, `ControlKind.stashed` (String constants).
  - `Surfaces.reload()` (used by Task 4).
  - `QuickAddControl`, `TasksLeftControl`, `StashedControl` (`ControlWidget`s), and `OpenAppIntent` (`AppIntent`).

- [ ] **Step 1: Create the reload entry point + kind constants**

Create `Shared/Surfaces.swift`:

```swift
import WidgetKit

/// Stable identifiers for the Control Center controls. Shared so the app can ask
/// ControlKit to reload a control by kind without importing the widget extension.
enum ControlKind {
    static let quickAdd = "QuickAddControl"
    static let tasksLeft = "TasksLeftControl"
    static let stashed = "StashedControl"
}

/// Single entry point to refresh every read-only surface after a data mutation:
/// home-screen / Lock Screen widgets, and — on iOS 18+ — Control Center controls.
enum Surfaces {
    static func reload() {
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadControls(ofKind: ControlKind.tasksLeft)
            ControlCenter.shared.reloadControls(ofKind: ControlKind.stashed)
        }
    }
}
```

- [ ] **Step 2: Create the controls**

Create `DailyTodoWidgets/TodoControls.swift`:

```swift
import WidgetKit
import SwiftUI
import AppIntents
import SwiftData

/// Brings 1List to the foreground (default screen — the list) from a control,
/// without a deep link. Used by the Tasks Left control.
@available(iOS 18.0, *)
struct OpenAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Open 1List"
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult { .result() }
}

// MARK: - Quick Add

/// Tap to open the app straight into new-task entry (reuses `dailytodo://add`).
@available(iOS 18.0, *)
struct QuickAddControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlKind.quickAdd) {
            ControlWidgetButton(action: OpenURLIntent(DeepLink.addURL)) {
                Label("Add Task", systemImage: "plus.circle")
            }
        }
        .displayName("Add Task")
    }
}

// MARK: - Tasks Left

/// Shows the open-task count; tap opens the app to the list.
@available(iOS 18.0, *)
struct TasksLeftControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlKind.tasksLeft, provider: Provider()) { count in
            ControlWidgetButton(action: OpenAppIntent()) {
                Label("\(count) left", systemImage: "checklist")
            }
        }
        .displayName("Tasks Left")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Int { 3 }
        func currentValue() async throws -> Int {
            ControlCounts.open(in: ModelContext(TaskStore.shared))
        }
    }
}

// MARK: - Stashed

/// Shows the stashed-task count; tap opens the stash drawer (`dailytodo://stash`).
@available(iOS 18.0, *)
struct StashedControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlKind.stashed, provider: Provider()) { count in
            ControlWidgetButton(action: OpenURLIntent(DeepLink.stashURL)) {
                Label("\(count) stashed", systemImage: "archivebox")
            }
        }
        .displayName("Stashed")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Int { 2 }
        func currentValue() async throws -> Int {
            ControlCounts.stashed(in: ModelContext(TaskStore.shared))
        }
    }
}
```

- [ ] **Step 3: Register the controls in the bundle**

In `DailyTodoWidgets/DailyTodoWidgetsBundle.swift`, replace the `body`:

```swift
@main
struct DailyTodoWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodoListWidget()
        TodoLiveActivity()
        if #available(iOS 18.0, *) {
            QuickAddControl()
            TasksLeftControl()
            StashedControl()
        }
    }
}
```

- [ ] **Step 4: Build to verify it compiles**

Run:
```bash
xcodebuild -scheme DailyTodo -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath build build
```
Expected: BUILD SUCCEEDED.

If `OpenURLIntent` fails to resolve, add `import AppIntents` (already present) and confirm the SDK is iOS 18+ (Xcode 26). `OpenURLIntent` is the system AppIntent for opening a URL and is a valid `ControlWidgetButton` action.

- [ ] **Step 5: Manually verify the controls appear**

```bash
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/DailyTodo.app
```
On the booted simulator: open Control Center → edit (＋) → "Add a Control" → search "1List". Expected: Add Task, Tasks Left, and Stashed appear. Add each; verify counts render and taps route (Add → entry, Tasks Left → list, Stashed → stash drawer).

- [ ] **Step 6: Commit**

```bash
git add Shared/Surfaces.swift DailyTodoWidgets/TodoControls.swift DailyTodoWidgets/DailyTodoWidgetsBundle.swift
git commit -m "Add Quick Add, Tasks Left, and Stashed Control Center controls"
```

---

### Task 4: Refresh controls on every mutation

Replace all 22 `WidgetCenter.shared.reloadAllTimelines()` call sites with `Surfaces.reload()` so controls refresh whenever widgets do.

**Files (each contains one or more `WidgetCenter.shared.reloadAllTimelines()` lines):**
- Modify: `Shared/StashReturn.swift` (1)
- Modify: `Shared/ToggleTaskIntent.swift` (1)
- Modify: `Shared/DailyCleanup.swift` (1)
- Modify: `DailyTodo/Views/StashSheet.swift` (8)
- Modify: `DailyTodo/Siri/TaskIntents.swift` (1, inside `refreshSurfaces()`)
- Modify: `DailyTodo/Views/TaskRow.swift` (2)
- Modify: `DailyTodo/Views/ListView.swift` (8)

**Interfaces:**
- Consumes: `Surfaces.reload()` (Task 3).

- [ ] **Step 1: Confirm the current call sites**

Run:
```bash
grep -rn "WidgetCenter.shared.reloadAllTimelines()" Shared DailyTodo DailyTodoWidgets --include="*.swift"
```
Expected: 22 matches across the files listed above. (`DailyTodoWidgets` reads counts but does not reload — 0 matches there.)

- [ ] **Step 2: Replace every call site with the unified reload**

Replace each occurrence of the exact line
`WidgetCenter.shared.reloadAllTimelines()`
with
`Surfaces.reload()`
across the seven files above. Each occurrence stands alone on its own line, so this is a literal line-for-line substitution. Run:

```bash
grep -rl "WidgetCenter.shared.reloadAllTimelines()" Shared DailyTodo --include="*.swift" \
  | xargs sed -i '' 's/WidgetCenter\.shared\.reloadAllTimelines()/Surfaces.reload()/g'
```

- [ ] **Step 3: Remove now-unused `import WidgetKit` where it was only for the reload**

For each modified file, check whether `WidgetKit` is still referenced (e.g. `WidgetCenter`, timeline types). Run:
```bash
grep -rn "WidgetKit\|WidgetCenter\|Timeline\|@available.*Widget" Shared/StashReturn.swift Shared/DailyCleanup.swift DailyTodo/Views/StashSheet.swift DailyTodo/Views/TaskRow.swift DailyTodo/Views/ListView.swift DailyTodo/Siri/TaskIntents.swift Shared/ToggleTaskIntent.swift
```
`Surfaces` lives in `Shared/` and needs no import. Leave `import WidgetKit` only in files that still use a WidgetKit symbol (e.g. `ToggleTaskIntent.swift` uses `WidgetKit` for `@main`-adjacent types? — keep if `WidgetCenter`/timeline symbols remain). Do not remove an import that is still in use; only delete `import WidgetKit` from a file where the grep shows no remaining WidgetKit symbol. When unsure, leave the import — an unused import is harmless and the build still succeeds.

- [ ] **Step 4: Verify no call sites remain**

Run:
```bash
grep -rn "reloadAllTimelines" Shared DailyTodo --include="*.swift"
```
Expected: no matches.

- [ ] **Step 5: Build and run the full test suite**

Run:
```bash
xcodebuild test -scheme DailyTodo -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath build -only-testing:DailyTodoTests
```
Expected: BUILD SUCCEEDED and all tests pass (including `ControlCountsTests`).

- [ ] **Step 6: Manually verify controls refresh**

With controls added to Control Center (Task 3, Step 5): add/complete/stash a task in the app, then reopen Control Center. Expected: "Tasks Left" and "Stashed" counts reflect the change.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Route all surface reloads through Surfaces.reload() to refresh controls"
```

---

## Self-Review

**Spec coverage:**
- Quick Add control → Task 3 (`QuickAddControl`, `OpenURLIntent(DeepLink.addURL)`). ✓
- Tasks Left control + value provider → Task 3 (`TasksLeftControl`, `ControlCounts.open`). ✓
- Stashed control opens the stash drawer → Task 2 (deep link + routing) + Task 3 (`StashedControl`, `OpenURLIntent(DeepLink.stashURL)`). ✓
- New `dailytodo://stash` deep link, `Router.stashRequested`, `onOpenURL` routing, `ListView` `.onChange` → Task 2. ✓
- iOS 18 availability gating with iOS 17 target preserved → every control `@available(iOS 18.0, *)`, bundle `if #available` (Task 3); Global Constraints. ✓
- Single reload entry point covering all widget-reload sites → `Surfaces.reload()` (Task 3) wired into all 22 sites (Task 4). ✓
- Counting logic test → Task 1 (`ControlCountsTests`). ✓
- Build still succeeds for iOS 17 target → Tasks 2-4 build steps. ✓
- File layout matches spec (`TodoControls.swift`, reload helper, edits to bundle/AppGroup/App/ListView) — spec named `Shared/ControlReload.swift`; plan uses `Shared/Surfaces.swift` as the single entry point that both widgets and controls reload through (a strict superset of the spec's intent, replacing all 22 sites rather than 3). ✓

**Placeholder scan:** No TBD/TODO/"handle edge cases"/"add validation"; every code step shows complete code. ✓

**Type consistency:** `ControlCounts.open(in:)`/`stashed(in:)` defined in Task 1, consumed verbatim in Task 3 providers. `ControlKind.{quickAdd,tasksLeft,stashed}` defined and consumed in Task 3; `tasksLeft`/`stashed` reloaded in `Surfaces.reload()`. `DeepLink.stashURL`/`stashHost` defined in Task 2, consumed in Task 3. `Router.stashRequested` defined and consumed in Task 2. `Surfaces.reload()` defined in Task 3, consumed in Task 4. ✓
