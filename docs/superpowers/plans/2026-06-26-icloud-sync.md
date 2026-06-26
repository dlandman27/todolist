# iCloud Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sync the one task list across the user's own Apple devices (iPhone, iPad, iOS-app-on-Mac) via their private iCloud/CloudKit database, automatically and invisibly.

**Architecture:** Switch the shared SwiftData store to a CloudKit-backed private database while keeping it in the App Group container (widget/Live Activity unaffected). Make `TaskItem` CloudKit-compatible (no unique constraint, all attributes defaulted). Fall back to a local-only store if CloudKit can't initialize.

**Tech Stack:** Swift, SwiftUI, SwiftData + CloudKit (NSPersistentCloudKitContainer under the hood), XCTest. Project `DailyTodo.xcodeproj`, test scheme `DailyTodo`.

## Global Constraints

- CloudKit **private** database only (personal sync; no sharing). Container id: `iCloud.com.dylanlandman.dailytodo`.
- Store stays in the App Group `group.com.dylanlandman.dailytodo` **and** gains `cloudKitDatabase: .private(...)`.
- CloudKit rules: **no `@Attribute(.unique)`**; every attribute optional or with a property-level default.
- Sync is invisible — no toggle, no status UI.
- Container init must **not** crash: on CloudKit failure, fall back to a local-only store.
- Low migration stakes (~3 live users) — rely on SwiftData lightweight migration + one upgrade-in-place check; do not build a staged versioned-schema migration.
- Unit tests use `isStoredInMemoryOnly: true` (no CloudKit). Sync itself is verified on-device.

## Test command

`iPhone 16` is not installed — use `iPhone 17`:

```bash
xcodebuild test -scheme DailyTodo -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:DailyTodoTests
```

## File Structure

- `Shared/TaskItem.swift` — drop `.unique`, add property defaults (CloudKit-compatible).
- `Shared/TaskStore.swift` — CloudKit store config + graceful local fallback.
- `DailyTodo/DailyTodo.entitlements` — iCloud/CloudKit container + services.
- `DailyTodoWidgets/DailyTodoWidgets.entitlements` — same (widget opens the shared config).
- Tests in `DailyTodoTests/` (add to existing `TaskActionsTests`/`StashTests` style).

> **Manual, not code (you in Xcode / Apple Developer):** these are required for sync to actually work and cannot be scripted here — they're called out in Task 3.

---

### Task 1: Make `TaskItem` CloudKit-compatible

**Files:**
- Modify: `Shared/TaskItem.swift`
- Test: `DailyTodoTests/StashTests.swift` (add one test)

**Interfaces:**
- Produces: `TaskItem` with no unique constraint and property-level defaults on `id`, `title`, `done`, `createdAt`. `init` signature is unchanged.

- [ ] **Step 1: Write the failing test**

Append to `DailyTodoTests/StashTests.swift` (inside the `StashTests` class or an extension with the same `makeContext()` helper):

```swift
extension StashTests {
    /// With the DB unique-constraint gone, `restore`'s own guard must still prevent a
    /// duplicate id from creating a second row.
    func testRestoreStillDedupesByIdWithoutUniqueConstraint() throws {
        let context = try makeContext()
        let id = UUID()
        let live = TaskItem(id: id, title: "Live")
        context.insert(live)
        try context.save()

        let ghost = TaskSnapshot(TaskItem(id: id, title: "Ghost"))
        TaskActions.restore([ghost], in: context)

        XCTAssertEqual(context.allTasks().count, 1)
        XCTAssertEqual(context.allTasks().first?.title, "Live")
    }
}
```

- [ ] **Step 2: Run the test to verify it passes against the current schema**

Run:
```bash
xcodebuild test -scheme DailyTodo -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:DailyTodoTests/StashTests/testRestoreStillDedupesByIdWithoutUniqueConstraint
```
Expected: PASS (the `restore` guard already exists; this test pins the behavior we must preserve when the constraint is removed).

- [ ] **Step 3: Make the schema CloudKit-compatible**

In `Shared/TaskItem.swift`, change the four property declarations (the `init` stays exactly as-is):

```swift
    var id: UUID = UUID()
    var title: String = ""
    var done: Bool = false
    /// Creation timestamp, used as a stable tiebreaker for ordering.
    var createdAt: Date = Date()
```

(Remove the `@Attribute(.unique)` from `id`. `completedAt`, `sortOrder`, `isStashed`, `stashReturnDate` already satisfy CloudKit — leave them.)

- [ ] **Step 4: Run the full unit suite**

Run:
```bash
xcodebuild test -scheme DailyTodo -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:DailyTodoTests
```
Expected: PASS — all existing tests plus the new one (the schema change is behavior-neutral; `init` is unchanged).

- [ ] **Step 5: Commit**

```bash
git add Shared/TaskItem.swift DailyTodoTests/StashTests.swift
git commit -m "Make TaskItem CloudKit-compatible (drop unique, add defaults)"
```

---

### Task 2: CloudKit store config + graceful fallback

**Files:**
- Modify: `Shared/TaskStore.swift`

**Interfaces:**
- Consumes: `TaskItem` (Task 1), `AppGroup.identifier`.
- Produces: `TaskStore.shared` backed by CloudKit in production, falling back to a local-only store on failure (no more `fatalError` as the first resort).

- [ ] **Step 1: Replace `makeContainer()` with a CloudKit-backed config + fallback**

In `Shared/TaskStore.swift`, replace the existing `makeContainer()`:

```swift
    static func makeContainer() -> ModelContainer {
        let schema = Schema([TaskItem.self])

        if isUITesting {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [config])
        }

        // Production: shared App Group store, mirrored to the user's private iCloud DB.
        let cloudConfig = ModelConfiguration(
            schema: schema,
            groupContainer: .identifier(AppGroup.identifier),
            cloudKitDatabase: .private("iCloud.com.dylanlandman.dailytodo")
        )
        if let container = try? ModelContainer(for: schema, configurations: [cloudConfig]) {
            return container
        }

        // CloudKit unavailable (no iCloud account, missing entitlement, etc.) — keep the
        // app fully usable offline with a local-only store in the same shared container.
        print("CloudKit container unavailable; falling back to local-only store.")
        let localConfig = ModelConfiguration(
            schema: schema,
            groupContainer: .identifier(AppGroup.identifier)
        )
        do {
            return try ModelContainer(for: schema, configurations: [localConfig])
        } catch {
            fatalError("Failed to create local ModelContainer: \(error)")
        }
    }
```

- [ ] **Step 2: Build (sim has no iCloud → exercises the fallback path)**

Run:
```bash
xcodebuild build -scheme DailyTodo -destination 'platform=iOS Simulator,name=iPhone 17'
```
Expected: `** BUILD SUCCEEDED **`. (On a simulator without iCloud configured, `cloudConfig` typically fails and the local fallback is used — the app still launches.)

- [ ] **Step 3: Run the unit suite (unchanged path)**

Run:
```bash
xcodebuild test -scheme DailyTodo -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:DailyTodoTests
```
Expected: PASS (tests use the in-memory path; production config change doesn't affect them).

- [ ] **Step 4: Commit**

```bash
git add Shared/TaskStore.swift
git commit -m "Back the store with CloudKit private DB; fall back to local on failure"
```

---

### Task 3: Entitlements + capabilities

**Files:**
- Modify: `DailyTodo/DailyTodo.entitlements`
- Modify: `DailyTodoWidgets/DailyTodoWidgets.entitlements`

**Interfaces:**
- Produces: both targets declare the CloudKit container so the shared store config can attach to it.

- [ ] **Step 1: Add the CloudKit keys to the app entitlements**

Replace `DailyTodo/DailyTodo.entitlements` contents with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.com.dylanlandman.dailytodo</string>
	</array>
	<key>com.apple.developer.icloud-container-identifiers</key>
	<array>
		<string>iCloud.com.dylanlandman.dailytodo</string>
	</array>
	<key>com.apple.developer.icloud-services</key>
	<array>
		<string>CloudKit</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 2: Add the same keys to the widget entitlements**

Replace `DailyTodoWidgets/DailyTodoWidgets.entitlements` contents with the identical `<dict>` (same three keys as Step 1).

- [ ] **Step 3: Build to confirm the plists are well-formed**

Run:
```bash
xcodebuild build -scheme DailyTodo -destination 'platform=iOS Simulator,name=iPhone 17'
```
Expected: `** BUILD SUCCEEDED **` (entitlements take full effect once the capability is enabled in Step 5; the build must still succeed).

- [ ] **Step 4: Commit**

```bash
git add DailyTodo/DailyTodo.entitlements DailyTodoWidgets/DailyTodoWidgets.entitlements
git commit -m "Add iCloud/CloudKit container to app and widget entitlements"
```

- [ ] **Step 5: MANUAL — enable capabilities in Xcode (cannot be scripted)**

In Xcode → the **DailyTodo** target → **Signing & Capabilities**:
1. **+ Capability → iCloud.** Check **CloudKit**. Under Containers, add/select `iCloud.com.dylanlandman.dailytodo` (create it if it's not there).
2. **+ Capability → Background Modes.** Check **Remote notifications** (lets CloudKit push changes while backgrounded).
3. Repeat the **iCloud → CloudKit** capability for the **DailyTodoWidgets** target with the same container.
4. Let Xcode update signing / provisioning profiles (re-sign as in your usual deployment flow).
5. (App Store, later) App Store Connect → the app → **Pricing and Availability** → check **make available on Apple Silicon Macs**.

Xcode may re-write the `.entitlements` files when you enable the capability — that's expected; commit any diff it produces.

---

## Verification (manual, on-device — sync is not unit-testable)

- [ ] **Upgrade-in-place (migration):** install the current 1.1 build, add a few tasks, then run the sync build over it. Confirm the existing tasks survive (lightweight migration). With ~3 users this is low-stakes, but verify once.
- [ ] **Two-device sync:** sign both devices into the same Apple ID (iPhone + iPad, or iPhone + the Mac once available). Add / edit / complete / **stash** a task on one; confirm it appears on the other within a few seconds, including stash state and deletes.
- [ ] **No-iCloud fallback:** sign out of iCloud on a device; confirm the app still launches and edits work locally (the fallback store).
- [ ] **Widget:** confirm the home-screen widget still shows the list after the store change.

---

## Self-Review

**Spec coverage:**
- CloudKit private DB + App Group coexist → Task 2 (`cloudConfig`). ✓
- Schema changes (drop unique, add defaults) → Task 1. ✓
- Invisible sync (no UI) → nothing to build; no UI added. ✓
- Graceful fallback (no fatalError first) → Task 2. ✓
- Entitlements for app + widget; manual capability/Background Modes/Mac availability → Task 3. ✓
- Migration kept lean + verified once → Verification section. ✓
- Conflict resolution = automatic → no code (documented in spec). ✓
- Testing: schema unit-tested; sync/migration on-device → Task 1 tests + Verification. ✓

**Placeholder scan:** No TBD/TODO; all code blocks complete. The manual Xcode steps are intentionally prose (they cannot be code).

**Type consistency:** `TaskItem` defaults and unchanged `init`; `ModelConfiguration(... groupContainer:cloudKitDatabase:)`; `AppGroup.identifier`; `TaskSnapshot(_:)` and `TaskActions.restore` used as they exist. Container id string `iCloud.com.dylanlandman.dailytodo` is identical in Task 2 and Task 3. ✓
