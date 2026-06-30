# Theming, Spec 2 — Custom Backgrounds

**Date:** 2026-06-30
**Status:** Approved — ready for implementation planning
**Part 2 of 2** (builds on Spec 1: dynamic foundation + accent, and the `CustomizeView` page)

## Goal

Let users set a custom background for the app's main surface — a solid color, a
gradient, or a photo from their library — with legibility safeguards so it always
stays readable. Lives on the `CustomizeView` page next to the accent.

Defaults are unchanged: background kind defaults to **None** (today's
`appBackground`), so existing users see no change until they opt in.

## Context & constraints

- Builds on Spec 1: `ThemeStore` (App Group defaults), `ThemeModel` (`@Observable`,
  injected at root), and `CustomizeView`.
- **App-only.** Backgrounds do not apply to the widget or Live Activity (a photo
  behind a Lock Screen activity isn't viable); the accent already carries the theme
  there. So background data does not need to be read cross-process — but it stays in
  `ThemeStore`/App Group for consistency and so it survives reinstalls of just the
  app.
- iOS 17.0 deployment target. Photo picking via `PhotosUI` `PhotosPicker`
  (iOS 16+ — fine).
- Performance: a picked photo is **downscaled** before storage/render; loaded once
  into `ThemeModel` and cached, not re-decoded per frame.

## Design

### Background model

`BackgroundKind`: `none` | `solid` | `gradient` | `photo` (raw `String`, stored).

`ThemeStore` gains (App Group defaults, all optional with safe defaults):
- `backgroundKind: BackgroundKind` (default `.none`)
- `backgroundColorHex: String` (solid; default a tasteful neutral)
- `gradientTopHex`, `gradientBottomHex: String` (gradient stops)
- Photo: stored as a downscaled JPEG file in the App Group container
  (`background.jpg`); a `backgroundPhotoToken` (timestamp string) in defaults marks
  presence and changes (so the model knows to reload).

Pure helpers (testable): kind round-trip from raw string, hex validation reuse
(`ThemeStore.normalizedHex`), gradient/solid config read/write.

### ThemeModel — observable background state

`ThemeModel` (from Spec 1) gains observed properties mirroring the store so changes
repaint live:
- `backgroundKind`, `backgroundColorHex`, `gradientTopHex`, `gradientBottomHex`
- `backgroundImage: UIImage?` (loaded from the App Group file when kind == photo)
- `setBackgroundKind(_:)`, `setSolid(_:)`, `setGradient(top:bottom:)`,
  `setPhoto(_ data: Data)` (downscale + write file + set token + load image),
  `clearPhoto()`. Each persists to `ThemeStore` and updates the observed property.

### ThemeBackground view (new)

A `ThemeBackground` view renders the chosen background **plus a legibility scrim**,
placed at the back of a surface's `ZStack` (replacing
`Color.appBackground.ignoresSafeArea()`):

- `.none` → `Color.appBackground` (today).
- `.solid` → the chosen color.
- `.gradient` → `LinearGradient` top→bottom of the two stops.
- `.photo` → `Image(uiImage:)` `.resizable().scaledToFill()` clipped, ignoring safe
  area.

**Legibility scrim:** over the background, overlay `Color.appBackground.opacity(k)`,
where `k` scales with how "busy" the kind is — `0` for none/solid, ~`0.10` for
gradient, ~`0.40` for photo. This veils any photo toward the active theme's base
color, so the existing `textPrimary`/`textSecondary` stay legible in both light and
dark without per-pixel contrast math. (A solid color the user picked is assumed
legible; no scrim.)

### Where it applies

The **main list** (`ListView`) and the **stash sheet** (`StashSheet`) — the two
list surfaces people look at. `SettingsView`/`CustomizeView` are `Form`s and keep
the flat `appBackground` (forms over photos read poorly). Each adopts the background
by swapping its base `Color.appBackground.ignoresSafeArea()` for `ThemeBackground()`.

Task rows on the main list are plain text today (no card). Over a photo, the scrim
carries contrast; no row-card change is required. (If a stronger separation is ever
wanted, rows can opt into `.ultraThinMaterial` — out of scope here.)

### CustomizeView — background section

Below the existing accent section, add a **Background** section:
- **Kind** picker (segmented): None / Color / Gradient / Photo.
- **Color** (when `.solid`): a `ColorPicker`.
- **Gradient** (when `.gradient`): a few preset gradient swatches + two `ColorPicker`s
  (top/bottom) for custom.
- **Photo** (when `.photo`): a `PhotosPicker` ("Choose Photo") + a thumbnail and a
  "Remove" button when set.
- The existing **live preview tile** at the top of `CustomizeView` renders over the
  chosen background (wrap it in `ThemeBackground` at a small size) so the user sees
  the result immediately.

No widget/Live Activity refresh needed for background changes (app-only); accent
changes keep their Spec 1 refresh.

## Files

**New**
- `Shared/ThemeBackground.swift` — `BackgroundKind` enum + the `ThemeBackground` view.
- `DailyTodoTests/ThemeBackgroundTests.swift` — kind round-trip, config read/write,
  scrim-opacity-by-kind.

**Edited**
- `Shared/ThemeStore.swift` — background keys + accessors; extend `ThemeModel` with
  background state + setters + photo load/save/downscale.
- `DailyTodo/Views/ListView.swift` — base background → `ThemeBackground()`.
- `DailyTodo/Views/StashSheet.swift` — base background → `ThemeBackground()`.
- `DailyTodo/Views/CustomizeView.swift` — background section + preview over background.

## Out of scope (YAGNI)

- Backgrounds on the widget / Live Activity / Control Center.
- Multiple saved backgrounds, per-list backgrounds, scheduled/auto backgrounds.
- Blur/parallax effects; user-adjustable scrim slider (fixed per-kind values).
- Theming `Form` screens (Settings/Customize) with photos.

## Testing

- **Unit (`ThemeBackgroundTests`):** `BackgroundKind` raw round-trip + unknown →
  `.none`; solid/gradient hex read/write round-trip via `ThemeStore`; scrim opacity
  is `0` for none/solid and larger for photo than gradient.
- **Manual/device:** set each kind; confirm the main list + stash recolor and stay
  legible (esp. a busy photo); relaunch persists; "Remove" photo reverts; fresh
  install shows today's flat background. Forms remain flat. Verify a large photo
  doesn't cause jank (downscaled).
- Build still succeeds for the iOS 17 target.
