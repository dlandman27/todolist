# Theming, Spec 1 — Dynamic Theme Foundation + Accent Color

**Date:** 2026-06-30
**Status:** Approved — ready for implementation planning
**Part 1 of 2** (Spec 2 = Custom Backgrounds, built right after on this foundation)

## Goal

Let users personalize the app's accent color (the brick red used everywhere), with
the change flowing automatically to the app, the home-screen widget, and the Live
Activity. This also lays the **dynamic theming foundation** that Spec 2 (custom
backgrounds) builds on.

Defaults are unchanged: until a user picks something, everything looks exactly as
it does today (brick red `#BC4749`).

## Context

- All color tokens live centrally in `Shared/Theme.swift` as static `let`s.
- `Color.brand` is the single accent token, used 28× across the app, widget
  (`DailyTodoWidgets/TodoListWidget.swift`), and Live Activity
  (`DailyTodoWidgets/TodoLiveActivity.swift`).
- The app already pushes cross-surface refreshes through `Surfaces.reload()`
  (widgets + controls) and `LiveActivityController.refresh()`.
- App theme (Light/Dark/System) is `AppTheme` + an `@AppStorage` picker in
  `SettingsView`. We keep it as-is; the accent applies in both modes.

## Design

### ThemeStore (new, `Shared/ThemeStore.swift`)

Single source of truth for theme values, backed by the App Group `UserDefaults`
so all three processes read the same data.

```
enum ThemeStore {
    static let accentKey = "themeAccentHex"
    static let defaultAccentHex = "BC4749"        // today's brick red

    static var accentHex: String { get set }       // reads/writes AppGroup.defaults
    static var accent: Color { Color(hex: accentHex) }

    static let presets: [String]                   // ~8 curated accent hexes
}
```

- `accentHex` getter falls back to `defaultAccentHex` when unset or malformed.
- Pure, unit-testable (no SwiftUI/WidgetKit).

### Theme.swift — tokens become dynamic

- `Color.brand` changes from a static `let` to a computed `var` returning
  `ThemeStore.accent`.
- `brandDark` (pressed/emphasis) and `brandTint` (soft wash) are **derived** from
  the accent so they stay coherent for any color:
  - `brandDark` = accent at ~0.8 brightness.
  - `brandTint` = accent blended toward the surface (light: toward white;
    dark: toward the dark surface) — a low-strength wash.
- Add small `UIColor` helpers: `adjustingBrightness(_:)` and
  `blended(with:fraction:)`. `stashAccent` and the neutral surface/text tokens are
  unchanged in Spec 1.

### Live update in-app

Add `@AppStorage(ThemeStore.accentKey, store: AppGroup.defaults)` at the app's root
view (`ListView`). Because `@AppStorage` observes the key via KVO, any write (from
the Settings picker, which binds the same key) invalidates every observing view, and
the recomputed `Color.brand` repaints the whole tree. No call sites change.

### Cross-process update (widget + Live Activity)

On any accent change, the Settings screen calls:
- `Surfaces.reload()` — refreshes widgets + Control Center controls.
- `LiveActivityController.refresh()` (via `@Environment`) — repaints a running
  Live Activity with the new accent.

The widget/LA read `Color.brand` fresh on each render, so they pick up the new value.

### Settings UI (`SettingsView`)

The existing **Appearance** section gains an accent control below "App Theme":
- A horizontal row of preset swatch circles (selected one ringed in `textPrimary`).
- A `ColorPicker` ("Custom") for any color.
- Tapping a swatch or changing the picker writes `ThemeStore.accentHex` and triggers
  the refreshes above. A small live preview (e.g. a filled sample row + checkbox)
  reflects the choice immediately.

Color↔hex conversion: reuse `Color(hex:)`; add a `Color`/`UIColor` → hex string
helper for the picker binding.

## Files

**New**
- `Shared/ThemeStore.swift` — accent storage, default, presets, derivation helpers.
- `DailyTodoTests/ThemeStoreTests.swift` — pure-logic tests.

**Edited**
- `Shared/Theme.swift` — `brand`/`brandDark`/`brandTint` become accent-derived;
  add `UIColor` brightness/blend helpers + a `Color→hex` helper.
- `DailyTodo/Views/SettingsView.swift` — accent swatches + picker + preview;
  trigger `Surfaces.reload()` and `live.refresh()` on change.
- `DailyTodo/Views/ListView.swift` — root `@AppStorage(accentKey)` to drive repaint.

## Out of scope (Spec 2 / YAGNI)

- Backgrounds (solid/gradient/photo) and their legibility safeguards — Spec 2.
- Theming the neutral surface/text tokens or `stashAccent` independently.
- Per-list or scheduled themes; importing/exporting themes.
- Accent on app icon.

## Testing

- **Unit (`ThemeStoreTests`):** default accent when unset; set/get round-trip;
  malformed hex falls back to default; `Color(hex:)`↔hex round-trip; `brandDark`
  is darker than `brand`; `brandTint` differs from both.
- **Manual/device:** pick a preset and a custom color → app, widget, and a running
  Live Activity all reflect it; relaunch persists; default install looks unchanged.
- Build still succeeds for the iOS 17 deployment target.
