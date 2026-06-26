# iCloud Sync — Design

**Date:** 2026-06-26
**Status:** Approved, ready for implementation plan

## Problem

The list lives only on the device (SwiftData in an App Group container). It doesn't
follow the user to another device, a new phone, the Mac, or survive a reinstall — and
there's no backup. We want the one list to sync automatically across the user's own
devices (iPhone, iPad, and the iOS-app-on-Mac) via their iCloud account.

## Scope

- **Personal sync only** — the user's **private** iCloud (CloudKit) database, their Apple
  ID. No sharing/collaboration with other people.
- **Mac access** is the free "run the iPhone app on Apple Silicon Macs" route — an App
  Store Connect availability checkbox, **no code/target work**. iCloud sync makes the list
  appear there.
- Sync is **invisible and automatic** (like Apple Notes/Reminders): no toggle, no status
  UI. Governed by the system iCloud account/settings.

## Decisions

| Question | Decision |
|----------|----------|
| Sync backend | SwiftData + CloudKit **private** database |
| Store location | Stays in the App Group container (widget/Live Activity keep reading it) **and** gains CloudKit mirroring |
| Mac | "Designed for iPhone/iPad" on Apple Silicon Macs — availability checkbox, no code |
| Sync UI | None — automatic, invisible |
| Not signed into iCloud | App works fully local; begins syncing once signed in |
| Conflict resolution | SwiftData/CloudKit automatic merge (last-writer-wins per field) |
| Container init failure | Fall back to a local store (fixes the existing `fatalError` techdebt) |

## Design

### Store configuration

`TaskStore.makeContainer()` switches its production `ModelConfiguration` to a
CloudKit-backed private database while keeping the App Group container:

```swift
ModelConfiguration(
    schema: schema,
    groupContainer: .identifier(AppGroup.identifier),
    cloudKitDatabase: .private("iCloud.com.dylanlandman.dailytodo")
)
```

The local store file remains in the shared App Group container; CloudKit mirrors it to the
private database. The widget and Live Activity keep reading the same local file.

The UI-testing path (`isStoredInMemoryOnly: true`) is unchanged — no CloudKit in tests.

### Schema changes (required for CloudKit)

CloudKit forbids unique constraints and requires every attribute to be optional or have a
default. `TaskItem` changes:

| Property | Now | After |
|----------|-----|-------|
| `id` | `@Attribute(.unique) var id: UUID` | `var id: UUID = UUID()` (drop `.unique`, add default) |
| `title` | `var title: String` | `var title: String = ""` |
| `done` | `var done: Bool` | `var done: Bool = false` |
| `createdAt` | `var createdAt: Date` | `var createdAt: Date = Date()` |
| `completedAt` | `var completedAt: Date?` | unchanged (already optional) |
| `sortOrder` | `var sortOrder: Int = 0` | unchanged (already defaulted) |
| `isStashed` | `var isStashed: Bool = false` | unchanged |
| `stashReturnDate` | `var stashReturnDate: Date? = nil` | unchanged |

No behavior change: the `init` still requires the same arguments; defaults only satisfy
CloudKit's storage rules. Dropping `.unique` is safe — ids are random UUIDs, nothing relies
on DB-enforced uniqueness, and `TaskActions.restore` already guards against re-inserting an
existing id.

### Migration (live 1.1 users)

The app is already shipped, so existing users have a local, non-CloudKit store with the
unique constraint. The plan must:

1. Define a versioned schema (`SchemaV1` = current shipped shape, `SchemaV2` = the
   CloudKit-compatible shape above) with a migration plan. Adding defaults is lightweight;
   removing the unique constraint is the part to verify.
2. On first launch of the sync build, the existing local store is adopted by
   `NSPersistentCloudKitContainer` (SwiftData) and its tasks are mirrored **up** to
   CloudKit automatically.
3. **Verify an upgrade-in-place** from a 1.1 store before shipping (install 1.1, add tasks,
   upgrade to the sync build, confirm tasks survive and then appear on a second device).

### Resilience / fallback

`makeContainer()` currently `fatalError`s on failure. New behavior: attempt the CloudKit
configuration; if `ModelContainer(...)` throws (e.g. account/entitlement issue), fall back
to a **local-only** `ModelConfiguration` (App Group, no CloudKit) so the app still launches
and works offline. Log the failure. (Closes the `fatalError`-on-init techdebt item.)

### Capabilities & entitlements

- **iCloud → CloudKit** capability enabled for the **DailyTodo** app target, with a CloudKit
  container `iCloud.com.dylanlandman.dailytodo`.
- The **DailyTodoWidgets** extension opens the same shared container config, so it also
  needs the iCloud/CloudKit entitlement + the same container id.
- Both `.entitlements` files gain `com.apple.developer.icloud-container-identifiers` and
  `com.apple.developer.icloud-services = [CloudKit]`.
- **Background modes → Remote notifications** on the app target so CloudKit can push changes
  while backgrounded.

**Who does what:**
- *Code (me):* store config, schema + migration, entitlement file edits, graceful fallback.
- *Apple Developer / Xcode (you):* enable the iCloud→CloudKit capability and create the
  container in Signing & Capabilities, then re-sign. Plus the App Store Connect "make
  available on Mac (Apple Silicon)" checkbox.

## Testing

Unit-testable (in-memory `ModelContext`, existing `DailyTodoTests` style):
- The `SchemaV2` `TaskItem` still constructs and persists correctly; the existing 43 tests
  (TaskActions, ordering, stash, cleanup) still pass against the new shape.
- A focused test that two `TaskItem`s with the same `id` can no longer be relied on to be
  deduped by the store (documents that `restore`'s guard is now the only dedupe) — i.e.
  `restore` still prevents duplicates.

Not unit-testable (manual, on-device):
- **Migration:** upgrade-in-place from a 1.1 build keeps existing tasks.
- **Sync:** two devices on the same Apple ID (e.g. iPhone + iPad, or iPhone + the Mac once
  available) — add/edit/complete/stash on one, see it on the other; verify deletes and
  stash state propagate.
- **No-iCloud fallback:** signed out of iCloud, the app still launches and edits locally.

## Out of scope / future

- Sharing a list with **other people** (CloudKit shared database) — deliberately not now.
- A native Mac Catalyst app — the free iOS-on-Mac route covers "see it on my Mac."
- Any sync status UI / manual toggle.
