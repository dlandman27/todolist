# Live Activity Lifecycle Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the Live Activity from silently disappearing by fixing zombie-activity detection and restarting the activity before iOS's 8-hour kill clock fires.

**Architecture:** A pure `LiveActivityPlanner` (Shared/) decides `.start`/`.update`/`.restart`/`.none` from snapshots of the current activities — same pattern as `RepeatSpawner.shouldSpawn`. `LiveActivityController` maps ActivityKit state to snapshots and executes the decision. The widget dims when the content goes stale.

**Tech Stack:** Swift / SwiftUI / ActivityKit, XCTest, XcodeGen.

**Spec:** `docs/2026-07-07-live-activity-lifecycle-design.md`

## Global Constraints

- Requires Xcode 26 / iOS 26 SDK (see AGENTS.md).
- The Xcode project is generated: after creating any new file, run `xcodegen generate` and commit the regenerated `DailyTodo.xcodeproj/project.pbxproj` alongside it. Never hand-edit the pbxproj.
- Test command (from repo root): `xcodebuild test -scheme DailyTodo -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath build -only-testing:DailyTodoTests`
- `Shared/` compiles into both the app and the widget extension — files there may only depend on what both targets link (Foundation is safe; no `LiveActivityController` references).

---

### Task 1: LiveActivityPlanner (pure decision) + tests

**Files:**
- Create: `Shared/LiveActivityPlanner.swift`
- Test: `DailyTodoTests/LiveActivityPlannerTests.swift`

**Interfaces:**
- Consumes: nothing (Foundation only).
- Produces: `enum LiveActivityAction: Equatable { case start, update, restart, none }`; `struct ActivitySnapshot { var isLive: Bool; var startedAt: Date? }`; `LiveActivityPlanner.action(userEnabled:systemEnabled:activities:now:maxAge:) -> LiveActivityAction`; constants `LiveActivityPlanner.maxAge` (1h) and `LiveActivityPlanner.systemLifetime` (8h). Tasks 2–3 rely on these exact names.

- [ ] **Step 1: Write the failing test**

Create `DailyTodoTests/LiveActivityPlannerTests.swift`:

```swift
import XCTest
@testable import DailyTodo

final class LiveActivityPlannerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func snap(live: Bool, ageMinutes: Double?) -> ActivitySnapshot {
        ActivitySnapshot(
            isLive: live,
            startedAt: ageMinutes.map { now.addingTimeInterval(-$0 * 60) }
        )
    }

    private func action(
        userEnabled: Bool = true,
        systemEnabled: Bool = true,
        _ activities: [ActivitySnapshot]
    ) -> LiveActivityAction {
        LiveActivityPlanner.action(
            userEnabled: userEnabled,
            systemEnabled: systemEnabled,
            activities: activities,
            now: now
        )
    }

    func testDisabledByUserDoesNothingEvenWithLiveActivity() {
        XCTAssertEqual(action(userEnabled: false, [snap(live: true, ageMinutes: 5)]), .none)
    }

    func testDisabledBySystemDoesNothing() {
        XCTAssertEqual(action(systemEnabled: false, [snap(live: true, ageMinutes: 5)]), .none)
    }

    func testNoActivitiesStartsFresh() {
        XCTAssertEqual(action([]), .start)
    }

    func testOnlyDeadActivitiesStartsFresh() {
        // The zombie case: a system-ended activity still listed by ActivityKit
        // must not be mistaken for a running one.
        XCTAssertEqual(action([snap(live: false, ageMinutes: 30)]), .start)
    }

    func testFreshLiveActivityUpdates() {
        XCTAssertEqual(action([snap(live: true, ageMinutes: 30)]), .update)
    }

    func testOldLiveActivityRestarts() {
        XCTAssertEqual(action([snap(live: true, ageMinutes: 120)]), .restart)
    }

    func testUnknownStartDateRestarts() {
        XCTAssertEqual(action([snap(live: true, ageMinutes: nil)]), .restart)
    }

    func testExactlyMaxAgeRestarts() {
        XCTAssertEqual(action([snap(live: true, ageMinutes: 60)]), .restart)
    }

    func testDeadPlusFreshLiveUpdates() {
        XCTAssertEqual(action([snap(live: false, ageMinutes: 300), snap(live: true, ageMinutes: 10)]), .update)
    }
}
```

- [ ] **Step 2: Regenerate the project and verify the test fails**

```bash
xcodegen generate
xcodebuild test -scheme DailyTodo -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath build -only-testing:DailyTodoTests/LiveActivityPlannerTests
```

Expected: BUILD FAILS — `cannot find 'ActivitySnapshot' in scope` (the planner doesn't exist yet). That is the failing state for this cycle.

- [ ] **Step 3: Write the minimal implementation**

Create `Shared/LiveActivityPlanner.swift`:

```swift
import Foundation

/// What `refresh()` should do with the Live Activity, decided purely from snapshots.
enum LiveActivityAction: Equatable {
    case start    // no usable activity — request a fresh one
    case update   // a young live activity exists — just push new content
    case restart  // live but aging/unknown — end it and request fresh to reset the 8h clock
    case none     // user opt-out or system-disabled
}

/// The testable essence of an `Activity`: is it actually presentable, and when did we request it?
struct ActivitySnapshot {
    var isLive: Bool      // activityState is .active or .stale
    var startedAt: Date?  // recorded at request time; nil if unknown
}

enum LiveActivityPlanner {
    /// Live activities older than this are restarted on the next refresh so the
    /// system's 8-hour kill clock resets while the user is still around.
    static let maxAge: TimeInterval = 60 * 60

    /// iOS ends every Live Activity this long after it was requested.
    static let systemLifetime: TimeInterval = 8 * 60 * 60

    static func action(
        userEnabled: Bool,
        systemEnabled: Bool,
        activities: [ActivitySnapshot],
        now: Date,
        maxAge: TimeInterval = LiveActivityPlanner.maxAge
    ) -> LiveActivityAction {
        guard userEnabled, systemEnabled else { return .none }
        guard let live = activities.first(where: { $0.isLive }) else { return .start }
        guard let startedAt = live.startedAt else { return .restart }
        return now.timeIntervalSince(startedAt) >= maxAge ? .restart : .update
    }
}
```

- [ ] **Step 4: Run the tests and verify they pass**

```bash
xcodebuild test -scheme DailyTodo -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath build -only-testing:DailyTodoTests/LiveActivityPlannerTests
```

Expected: TEST SUCCEEDED, 9 tests passing.

- [ ] **Step 5: Commit**

```bash
git add Shared/LiveActivityPlanner.swift DailyTodoTests/LiveActivityPlannerTests.swift DailyTodo.xcodeproj/project.pbxproj
git commit -m "Add pure LiveActivityPlanner decision with tests"
```

---

### Task 2: Controller executes planner decisions

**Files:**
- Modify: `DailyTodo/LiveActivityController.swift` (full replacement below)
- Modify: `Shared/LiveActivityBridge.swift` (add shared start-date storage)

**Interfaces:**
- Consumes: `LiveActivityAction`, `ActivitySnapshot`, `LiveActivityPlanner` from Task 1.
- Produces: `LiveActivityBridge.startedAtKey: String`, `LiveActivityBridge.staleDate() -> Date?` (used by Task 3); controller public API unchanged (`refresh()`, `start()`, `stop()`, `toggle()`, `isEnabled`, `isRunning`, `systemEnabled`).

- [ ] **Step 1: Add start-date storage to the bridge**

In `Shared/LiveActivityBridge.swift`, add inside `enum LiveActivityBridge`:

```swift
    /// When the current activity was requested, persisted in the App Group so both
    /// the app (which starts activities) and the extension (which updates them) agree.
    static let startedAtKey = "liveActivityStartedAt"

    /// The moment the system will kill the current activity — content is stale from then on.
    static func staleDate() -> Date? {
        guard let startedAt = UserDefaults(suiteName: AppGroup.identifier)?
            .object(forKey: startedAtKey) as? Date else { return nil }
        return startedAt.addingTimeInterval(LiveActivityPlanner.systemLifetime)
    }
```

- [ ] **Step 2: Replace the controller**

Replace the body of `DailyTodo/LiveActivityController.swift` with:

```swift
import ActivityKit
import SwiftData
import Foundation
import Observation

/// Owns the lifecycle of the list's Live Activity from the app side: start, keep updated, stop.
/// The user can opt out; the choice persists in the App Group defaults.
@MainActor
@Observable
final class LiveActivityController {
    static let shared = LiveActivityController()

    private let defaults = UserDefaults(suiteName: AppGroup.identifier)
    private let enabledKey = "liveActivityEnabled"

    private(set) var isRunning = false

    private init() {
        syncRunningState()
    }

    /// Whether the user wants the list pinned to the lock screen. Defaults to on.
    var isEnabled: Bool {
        get { defaults?.object(forKey: enabledKey) as? Bool ?? true }
        set { defaults?.set(newValue, forKey: enabledKey) }
    }

    /// Whether Live Activities are permitted by the system (Settings → toggle).
    var systemEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Start, update, or restart the activity so it reflects the current list —
    /// and so the system's 8-hour kill clock keeps getting reset while the user is active.
    func refresh() {
        guard !TaskStore.isUITesting else { return }

        let storedStart = defaults?.object(forKey: LiveActivityBridge.startedAtKey) as? Date
        let snapshots = Activity<TodoActivityAttributes>.activities.map {
            ActivitySnapshot(isLive: Self.isLive($0.activityState), startedAt: storedStart)
        }

        switch LiveActivityPlanner.action(
            userEnabled: isEnabled,
            systemEnabled: systemEnabled,
            activities: snapshots,
            now: Date()
        ) {
        case .none:
            syncRunningState()
        case .update:
            let content = ActivityContent(
                state: LiveActivityBridge.contentState(),
                staleDate: LiveActivityBridge.staleDate()
            )
            if let live = Activity<TodoActivityAttributes>.activities
                .first(where: { Self.isLive($0.activityState) }) {
                Task { await live.update(content) }
            }
            isRunning = true
        case .start, .restart:
            requestFresh()
        }
    }

    /// Pin the list to the lock screen.
    func start() {
        isEnabled = true
        refresh()
    }

    /// Remove the list from the lock screen and remember the opt-out.
    func stop() {
        isEnabled = false
        defaults?.removeObject(forKey: LiveActivityBridge.startedAtKey)
        for activity in Activity<TodoActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        isRunning = false
    }

    func toggle() {
        // Re-derive from reality first: the OS may have ended the activity (time limit,
        // user dismissal) without the app knowing, leaving `isRunning` stale. Without
        // this, the first tap after a silent end takes the wrong branch and looks dead.
        syncRunningState()
        isRunning ? stop() : start()
    }

    /// End everything (live or zombie) and request a fresh activity, resetting the 8h clock.
    private func requestFresh() {
        let existing = Activity<TodoActivityAttributes>.activities
        let startedAt = Date()
        defaults?.set(startedAt, forKey: LiveActivityBridge.startedAtKey)
        let content = ActivityContent(
            state: LiveActivityBridge.contentState(),
            staleDate: startedAt.addingTimeInterval(LiveActivityPlanner.systemLifetime)
        )
        Task {
            for activity in existing {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            do {
                _ = try Activity.request(
                    attributes: TodoActivityAttributes(),
                    content: content,
                    pushType: nil
                )
                isRunning = true
            } catch {
                print("Live Activity start failed: \(error)")
                isRunning = false
            }
        }
    }

    private static func isLive(_ state: ActivityState) -> Bool {
        state == .active || state == .stale
    }

    private func syncRunningState() {
        isRunning = Activity<TodoActivityAttributes>.activities
            .contains { Self.isLive($0.activityState) }
    }
}
```

- [ ] **Step 3: Build and run the full unit suite**

```bash
xcodebuild test -scheme DailyTodo -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath build -only-testing:DailyTodoTests
```

Expected: TEST SUCCEEDED (all existing suites plus the 9 planner tests).

- [ ] **Step 4: Commit**

```bash
git add DailyTodo/LiveActivityController.swift Shared/LiveActivityBridge.swift
git commit -m "Restart aging Live Activities and ignore zombie ones"
```

---

### Task 3: Stale date on extension updates + stale dimming in the widget

**Files:**
- Modify: `Shared/LiveActivityBridge.swift:18-23` (`updateRunningActivities`)
- Modify: `DailyTodoWidgets/TodoLiveActivity.swift:10-13, 56-89`

**Interfaces:**
- Consumes: `LiveActivityBridge.staleDate()` from Task 2.
- Produces: nothing new.

- [ ] **Step 1: Use the stale date in extension-side updates**

In `Shared/LiveActivityBridge.swift`, change `updateRunningActivities`:

```swift
    static func updateRunningActivities() async {
        let state = contentState()
        for activity in Activity<TodoActivityAttributes>.activities {
            await activity.update(ActivityContent(state: state, staleDate: staleDate()))
        }
    }
```

- [ ] **Step 2: Dim the lock-screen view when stale**

In `DailyTodoWidgets/TodoLiveActivity.swift`, pass staleness into the lock-screen view:

```swift
        ActivityConfiguration(for: TodoActivityAttributes.self) { context in
            LockScreenLiveView(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(Color.appBackground)
                .activitySystemActionForegroundColor(Color.brand)
        } dynamicIsland: { context in
```

And in `LockScreenLiveView`:

```swift
private struct LockScreenLiveView: View {
    let state: TodoActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ... existing content unchanged ...
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .opacity(isStale ? 0.55 : 1)
    }
}
```

(Only the property, the signature, and the trailing `.opacity` modifier change; the VStack content stays as-is.)

- [ ] **Step 3: Build both targets and run the suite**

```bash
xcodebuild -scheme DailyTodo -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath build build
xcodebuild test -scheme DailyTodo -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath build -only-testing:DailyTodoTests
```

Expected: BUILD SUCCEEDED, TEST SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Shared/LiveActivityBridge.swift DailyTodoWidgets/TodoLiveActivity.swift
git commit -m "Mark Live Activity content stale at the 8h limit and dim when stale"
```

---

### Task 4: End-to-end smoke check on the simulator

**Files:** none (verification only).

- [ ] **Step 1: Install and launch**

```bash
xcrun simctl list devices booted   # boot "iPhone 17 Pro Max" first if empty
xcodebuild -scheme DailyTodo -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath build build \
  && xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/DailyTodo.app \
  && xcrun simctl launch booted com.dylanlandman.dailytodo
```

- [ ] **Step 2: Verify the activity appears and survives a refresh cycle**

- Toggle a task in the app, then lock the simulator (Device → Lock) and confirm the Live Activity shows on the lock screen with the current list.
- Relaunch the app and check logs for a start failure:

```bash
xcrun simctl spawn booted log show --last 3m --style compact --predicate 'process == "DailyTodo"' | grep -i "live activity" || echo "no failures logged"
```

Expected: no "Live Activity start failed" lines.

- [ ] **Step 3: Verify the zombie path via the Customize toggle**

In Customize (Beta), toggle the Live Activity off and on — the pinned list should disappear and come back. This exercises `stop()` → `start()` → `requestFresh()`.
