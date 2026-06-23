# AGENTS.md

Guidance for coding agents working in this repo.

## Project

DailyTodo — a single-list iOS to-do app (SwiftUI + SwiftData) with a home-screen
widget and a Live Activity. Requires Xcode 26 / iOS 26 SDK.

Key facts:
- **Xcode project:** `DailyTodo.xcodeproj`
- **App scheme:** `DailyTodo` (also a `DailyTodoWidgets` scheme for the extension)
- **Bundle identifier:** `com.dylanlandman.dailytodo`
- **Targets:** `DailyTodo` (app), `DailyTodoWidgets` (widget + Live Activity),
  `DailyTodoTests` (unit), `DailyTodoUITests` (UI)
- **Shared code:** `Shared/` is compiled into both the app and the widget
  extension (model, store, ordering, theme, intents).

## Build, install, and run on the Simulator

These commands are the verified happy path. `-derivedDataPath build` keeps build
products in `./build/` so the `.app` path below is stable.

### 1. Pick / boot a simulator

Target the already-booted simulator by name (no UDID needed):

```bash
# See what's booted
xcrun simctl list devices booted

# Boot one if nothing is (example device)
xcrun simctl boot "iPhone 17 Pro Max"
open -a Simulator
```

### 2. Build

```bash
xcodebuild -scheme DailyTodo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -derivedDataPath build build
```

To target a specific booted device instead, use its UDID from step 1:
`-destination 'id=<UDID>'`.

### 3. Install + launch on the booted simulator

```bash
APP=build/Build/Products/Debug-iphonesimulator/DailyTodo.app
xcrun simctl install booted "$APP"
xcrun simctl launch booted com.dylanlandman.dailytodo
```

A rebuild + reinstall + relaunch one-liner:

```bash
xcodebuild -scheme DailyTodo -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath build build \
  && xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/DailyTodo.app \
  && xcrun simctl launch booted com.dylanlandman.dailytodo
```

## Run the unit tests

```bash
xcodebuild test -scheme DailyTodo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -derivedDataPath build \
  -only-testing:DailyTodoTests
```

Drop `-only-testing:DailyTodoTests` to also run the UI tests. The pure logic
(ordering, reordering, model) lives in `DailyTodoTests/TaskLogicTests.swift` and
runs fast — prefer adding logic there over UI tests.

## Inspect a running build

```bash
# Screenshot the booted simulator
xcrun simctl io booted screenshot /tmp/dailytodo.png

# Stream this app's logs (NSLog / os_log). Use a unique marker string when
# adding temporary logging so it's easy to grep.
xcrun simctl spawn booted log stream --style compact \
  --predicate 'process == "DailyTodo"'

# Or query the log store retroactively (more reliable than live streaming):
xcrun simctl spawn booted log show --last 3m --style compact \
  --predicate 'process == "DailyTodo"'
```

Note: macOS has no `timeout` builtin — run long-lived `log stream` as a
background process and stop it, or prefer `log show --last <N>m`.

## Notes

- There is no `CLAUDE.md`; this file is the single source of agent guidance.
- The `build/` directory is local build output — don't commit it.
