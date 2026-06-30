# Theming 1/2 — Dynamic Foundation + Accent Color — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users pick the app's accent color (presets + custom), flowing to the app, widget, and Live Activity, on a dynamic theming foundation that Spec 2 (backgrounds) builds on.

**Architecture:** A pure `ThemeStore` (App Group `UserDefaults`) holds the accent hex. `Theme.swift`'s `brand`/`brandDark`/`brandTint` become computed from it (derived shades), so all 28 existing `Color.brand` call sites inherit the change untouched. A root `@AppStorage` repaints the app; `Surfaces.reload()` + `LiveActivityController.refresh()` push it cross-process.

**Tech Stack:** Swift, SwiftUI, WidgetKit, SwiftData, XCTest. XcodeGen (`project.yml`) → `xcodebuild`.

## Global Constraints

- App deployment target stays **iOS 17.0** (`project.yml`).
- Shared logic lives in **`Shared/`** (compiled into app + widget). Read theme via `ThemeStore`; never duplicate the hex.
- **Default accent is `BC4749`** (today's brick red). A clean install must look identical to today.
- New files under already-globbed folders (`Shared/`, `DailyTodoTests/`) require **`xcodegen generate`** before they compile (the project lists sources explicitly).
- Build/test: `xcodebuild [test] -scheme DailyTodo -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath build`.

---

### Task 1: `ThemeStore` accent storage + presets

Pure storage + hex helpers, unit-testable without SwiftUI/WidgetKit.

**Files:**
- Create: `Shared/ThemeStore.swift`
- Create: `DailyTodoTests/ThemeStoreTests.swift`

**Interfaces:**
- Consumes: `AppGroup.defaults` (existing, `Shared/AppGroup.swift`); `Color(hex: UInt32)` (existing, `Shared/Theme.swift`).
- Produces:
  - `ThemeStore.accentKey: String` = `"themeAccentHex"`
  - `ThemeStore.defaultAccentHex: String` = `"BC4749"`
  - `ThemeStore.presets: [String]`
  - `ThemeStore.accentHex: String` (get/set, App Group backed, validated)
  - `ThemeStore.accent: Color`
  - `ThemeStore.normalizedHex(_ raw: String?) -> String?`
  - `ThemeStore.hexValue(_ hex: String) -> UInt32`

- [ ] **Step 1: Write the failing test**

Create `DailyTodoTests/ThemeStoreTests.swift`:

```swift
import XCTest
@testable import DailyTodo

final class ThemeStoreTests: XCTestCase {

    func testNormalizedHexAcceptsValidForms() {
        XCTAssertEqual(ThemeStore.normalizedHex("bc4749"), "BC4749")
        XCTAssertEqual(ThemeStore.normalizedHex("#BC4749"), "BC4749")
        XCTAssertEqual(ThemeStore.normalizedHex("  BC4749  "), "BC4749")
    }

    func testNormalizedHexRejectsInvalid() {
        XCTAssertNil(ThemeStore.normalizedHex(nil))
        XCTAssertNil(ThemeStore.normalizedHex("xyz123"))
        XCTAssertNil(ThemeStore.normalizedHex("BC474"))     // 5 digits
        XCTAssertNil(ThemeStore.normalizedHex("BC474900"))  // 8 digits
    }

    func testHexValueParsesToUInt32() {
        XCTAssertEqual(ThemeStore.hexValue("BC4749"), 0xBC4749)
        XCTAssertEqual(ThemeStore.hexValue("FFFFFF"), 0xFFFFFF)
        XCTAssertEqual(ThemeStore.hexValue("000000"), 0x000000)
    }

    func testPresetsAreCanonicalAndDefaultIsFirst() {
        XCTAssertEqual(ThemeStore.presets.first, ThemeStore.defaultAccentHex)
        for hex in ThemeStore.presets {
            XCTAssertEqual(ThemeStore.normalizedHex(hex), hex, "preset \(hex) must already be canonical")
        }
    }

    func testDefaultAccentIsBrick() {
        XCTAssertEqual(ThemeStore.defaultAccentHex, "BC4749")
    }
}
```

- [ ] **Step 2: Create the source file, then regenerate so tests compile**

Create `Shared/ThemeStore.swift`:

```swift
import SwiftUI

/// Single source of truth for the user's theme choices, backed by the App Group
/// defaults so the app, widget, and Live Activity all read the same values.
/// Spec 1 covers the accent color; Spec 2 extends this with backgrounds.
enum ThemeStore {
    static let accentKey = "themeAccentHex"
    /// Today's brick red — the default until the user picks something else.
    static let defaultAccentHex = "BC4749"

    /// Curated accent presets (6-digit hex, no `#`). First is the default brick.
    static let presets: [String] = [
        "BC4749", // Brick (default)
        "2D6FB0", // Ocean
        "3E7D5A", // Forest
        "7A4F9E", // Grape
        "E0723C", // Sunset
        "C84B6E", // Rose
        "5B6472", // Slate
        "C99A2E", // Gold
    ]

    /// Stored accent as canonical hex; falls back to the default when unset/invalid.
    static var accentHex: String {
        get { normalizedHex(AppGroup.defaults?.string(forKey: accentKey)) ?? defaultAccentHex }
        set { AppGroup.defaults?.set(normalizedHex(newValue) ?? defaultAccentHex, forKey: accentKey) }
    }

    static var accent: Color { Color(hex: hexValue(accentHex)) }

    /// Validate a 6-digit hex (optional leading `#`), returning canonical UPPERCASE
    /// 6 chars, or nil if malformed.
    static func normalizedHex(_ raw: String?) -> String? {
        guard var s = raw?.trimmingCharacters(in: .whitespaces) else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, s.allSatisfy(\.isHexDigit) else { return nil }
        return s.uppercased()
    }

    /// `UInt32` for `Color(hex:)`. Assumes already-validated input; defaults to brick.
    static func hexValue(_ hex: String) -> UInt32 {
        UInt32(hex, radix: 16) ?? 0xBC4749
    }
}
```

Run: `xcodegen generate`
Expected: regenerates `DailyTodo.xcodeproj` including the two new files.

- [ ] **Step 3: Run tests to verify they pass**

Run: `xcodebuild test -scheme DailyTodo -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath build -only-testing:DailyTodoTests/ThemeStoreTests`
Expected: PASS (5 tests). (Ignore CloudKit "no iCloud account" log noise.)

- [ ] **Step 4: Commit**

```bash
git add Shared/ThemeStore.swift DailyTodoTests/ThemeStoreTests.swift project.yml DailyTodo.xcodeproj/project.pbxproj
git commit -m "Add ThemeStore for the dynamic accent color"
```

---

### Task 2: Make `Theme.swift` tokens accent-derived

Turn `brand`/`brandDark`/`brandTint` into computed values derived from `ThemeStore`, and add the color helpers the Settings picker needs.

**Files:**
- Modify: `Shared/Theme.swift`
- Create: `DailyTodoTests/ThemeColorTests.swift`

**Interfaces:**
- Consumes: `ThemeStore.accentHex`, `ThemeStore.hexValue` (Task 1); existing private `rgb(_:)`/`dynamic(_:_:)` in `Theme.swift`.
- Produces:
  - `UIColor.adjustingBrightness(_ factor: CGFloat) -> UIColor`
  - `UIColor.blended(with: UIColor, fraction: CGFloat) -> UIColor`
  - `Color.toHex() -> String`
  - `Color.brand` / `.brandDark` / `.brandTint` now computed (accent-derived).

- [ ] **Step 1: Write the failing test**

Create `DailyTodoTests/ThemeColorTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import DailyTodo

final class ThemeColorTests: XCTestCase {

    private func rgbSum(_ hex: String) -> Int {
        let v = Int(ThemeStore.hexValue(hex))
        return ((v >> 16) & 0xFF) + ((v >> 8) & 0xFF) + (v & 0xFF)
    }

    func testColorToHexRoundTripsWithInit() {
        XCTAssertEqual(Color(hex: 0xBC4749).toHex(), "BC4749")
        XCTAssertEqual(Color(hex: 0xFFFFFF).toHex(), "FFFFFF")
        XCTAssertEqual(Color(hex: 0x000000).toHex(), "000000")
    }

    func testAdjustingBrightnessDarkens() {
        let base = UIColor(red: 0.7, green: 0.3, blue: 0.3, alpha: 1)
        let darker = base.adjustingBrightness(0.8)
        var b0: CGFloat = 0, b1: CGFloat = 0, x: CGFloat = 0
        base.getHue(&x, saturation: &x, brightness: &b0, alpha: &x)
        darker.getHue(&x, saturation: &x, brightness: &b1, alpha: &x)
        XCTAssertLessThan(b1, b0)
    }

    func testBlendEndpoints() {
        let a = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
        let b = UIColor(red: 0, green: 0, blue: 1, alpha: 1)
        XCTAssertEqual(Color(uiColor: a.blended(with: b, fraction: 0)).toHex(), "FF0000")
        XCTAssertEqual(Color(uiColor: a.blended(with: b, fraction: 1)).toHex(), "0000FF")
    }

    func testBrandDarkIsDarkerThanBrand() {
        // With no override, accent == default brick.
        XCTAssertLessThan(rgbSum(Color.brandDark.toHex()), rgbSum(Color.brand.toHex()))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme DailyTodo -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath build -only-testing:DailyTodoTests/ThemeColorTests` (after `xcodegen generate` so the new test file is in the project)
Expected: FAIL to compile — `value of type 'Color' has no member 'toHex'` / `UIColor` has no member `adjustingBrightness`.

- [ ] **Step 3: Implement the helpers and make tokens dynamic**

In `Shared/Theme.swift`, replace the `extension UIColor { // MARK: Brand … }` brand lines and the `Color` brand lines so they're computed, and add helpers. Specifically:

Replace the three brand `UIColor` statics:

```swift
    // MARK: Brand
    static let appBrand = rgb(0xBC4749)
    static let appBrandDark = rgb(0x97383A)
    static let appBrandTint = dynamic(light: 0xF6DEDF, dark: 0x4A2E30)
```

with accent-derived computed versions:

```swift
    // MARK: Brand (accent-derived — see ThemeStore)
    static var appBrand: UIColor { rgb(ThemeStore.hexValue(ThemeStore.accentHex)) }
    static var appBrandDark: UIColor { appBrand.adjustingBrightness(0.8) }
    static var appBrandTint: UIColor {
        UIColor { trait in
            let towards: UIColor = trait.userInterfaceStyle == .dark ? rgb(0x171113) : .white
            let frac: CGFloat = trait.userInterfaceStyle == .dark ? 0.72 : 0.82
            return appBrand.blended(with: towards, fraction: frac)
        }
    }
```

Replace the three brand `Color` statics:

```swift
    /// Primary brand color. Hex #BC4749.
    static let brand = Color(uiColor: .appBrand)
    /// Darker brand shade for pressed / emphasis states. Hex #97383A.
    static let brandDark = Color(uiColor: .appBrandDark)
    /// Soft brand wash for subtle fills and selected rows.
    static let brandTint = Color(uiColor: .appBrandTint)
```

with:

```swift
    /// Primary brand/accent color (user-customizable via ThemeStore).
    static var brand: Color { Color(uiColor: .appBrand) }
    /// Darker accent shade for pressed / emphasis states.
    static var brandDark: Color { Color(uiColor: .appBrandDark) }
    /// Soft accent wash for subtle fills and selected rows.
    static var brandTint: Color { Color(uiColor: .appBrandTint) }
```

Add the helpers at the end of `Shared/Theme.swift`:

```swift
extension UIColor {
    /// Scale HSB brightness by `factor` (clamped 0...1).
    func adjustingBrightness(_ factor: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        return UIColor(hue: h, saturation: s, brightness: max(0, min(1, b * factor)), alpha: a)
    }

    /// Linear RGBA blend toward `other` by `fraction` (0 = self, 1 = other).
    func blended(with other: UIColor, fraction: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let f = max(0, min(1, fraction))
        return UIColor(red: r1 + (r2 - r1) * f, green: g1 + (g2 - g1) * f,
                       blue: b1 + (b2 - b1) * f, alpha: a1 + (a2 - a1) * f)
    }
}

extension Color {
    /// 6-digit UPPERCASE sRGB hex (no `#`) — used to persist a picked color.
    func toHex() -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        let c = { (v: CGFloat) in Int((max(0, min(1, v)) * 255).rounded()) }
        return String(format: "%02X%02X%02X", c(r), c(g), c(b))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme DailyTodo -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath build -only-testing:DailyTodoTests/ThemeColorTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Shared/Theme.swift DailyTodoTests/ThemeColorTests.swift DailyTodo.xcodeproj/project.pbxproj
git commit -m "Derive brand/brandDark/brandTint from the accent; add color helpers"
```

---

### Task 3: Repaint the app live on accent change

Make the root view observe the accent key so the whole tree repaints when it changes (the widget/LA are handled in Task 4's refresh calls).

**Files:**
- Modify: `DailyTodo/Views/ListView.swift`

**Interfaces:**
- Consumes: `ThemeStore.accentKey`, `ThemeStore.defaultAccentHex` (Task 1); `AppGroup.defaults` (existing).

- [ ] **Step 1: Add the observing property**

In `DailyTodo/Views/ListView.swift`, alongside the other `@AppStorage` (near `listName`), add:

```swift
    // Observing the accent key repaints the whole list (and its pushed Settings
    // screen) the moment the accent changes — Color.brand re-reads ThemeStore.
    @AppStorage(ThemeStore.accentKey, store: AppGroup.defaults) private var accentHex = ThemeStore.defaultAccentHex
```

Then apply it as the navigation tint so the value is used (no "unused" warning) and nav-bar controls also pick up the accent. On the `NavigationStack { … }` in `body`, add after its closing brace modifiers:

```swift
            .tint(Color.brand)
```

(Place it among the existing `NavigationStack` modifiers, e.g. right after `.sheet(isPresented: $showStash) { … }`.)

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -scheme DailyTodo -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath build build`
Expected: BUILD SUCCEEDED, no "unused variable" warning for `accentHex`.

- [ ] **Step 3: Commit**

```bash
git add DailyTodo/Views/ListView.swift
git commit -m "Repaint the app when the accent changes; tint nav with the accent"
```

---

### Task 4: Accent picker in Settings (swatches + custom + preview)

Add the accent UI and wire the cross-process refresh.

**Files:**
- Modify: `DailyTodo/Views/SettingsView.swift`
- Test: `DailyTodoUITests/TaskFlowUITests.swift` (one smoke test)

**Interfaces:**
- Consumes: `ThemeStore` (Task 1); `Color(hex:)`, `Color.toHex()` (Task 2); `Surfaces.reload()` (`Shared/Surfaces.swift`, existing); `LiveActivityController` (existing, via `@Environment`); `Haptics` (existing).

- [ ] **Step 1: Add environment + storage to `SettingsView`**

At the top of `SettingsView` (with the other `@AppStorage`):

```swift
    @Environment(LiveActivityController.self) private var live
    @AppStorage(ThemeStore.accentKey, store: AppGroup.defaults) private var accentHex = ThemeStore.defaultAccentHex
```

- [ ] **Step 2: Add the accent section + helpers**

Add this `Section` inside the `Form`, immediately after the existing "Appearance" `Section` (the App Theme picker). Use a new `Accent` header:

```swift
                Section {
                    // Preset swatches.
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
                        ForEach(ThemeStore.presets, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: ThemeStore.hexValue(hex)))
                                .frame(height: 34)
                                .overlay {
                                    if accentHex == hex {
                                        Circle().stroke(Color.textPrimary, lineWidth: 2).padding(-3)
                                    }
                                }
                                .contentShape(Circle())
                                .onTapGesture { setAccent(hex) }
                                .accessibilityIdentifier("accent-\(hex)")
                                .accessibilityLabel("Accent \(hex)")
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.appSurface)

                    ColorPicker(selection: accentBinding, supportsOpacity: false) {
                        Label("Custom", systemImage: "eyedropper")
                            .foregroundStyle(Color.textPrimary)
                    }
                    .listRowBackground(Color.appSurface)
                } header: {
                    Text("Accent")
                } footer: {
                    Text("Sets the highlight color across the app, widget, and Live Activity.")
                }
```

Add these members to `SettingsView`:

```swift
    /// Two-way bridge between the stored hex and SwiftUI's ColorPicker.
    private var accentBinding: Binding<Color> {
        Binding(
            get: { Color(hex: ThemeStore.hexValue(accentHex)) },
            set: { setAccent($0.toHex()) }
        )
    }

    /// Persist a new accent and push it to every surface.
    private func setAccent(_ hex: String) {
        accentHex = ThemeStore.normalizedHex(hex) ?? ThemeStore.defaultAccentHex
        Haptics.selection()
        Surfaces.reload()          // home-screen widget + Control Center controls
        live.refresh()             // a running Live Activity
    }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -scheme DailyTodo -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath build build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Add a UI smoke test**

In `DailyTodoUITests/TaskFlowUITests.swift`, add:

```swift
    func testAccentSwatchSelectable() {
        app.buttons["settings"].tap()
        let ocean = app.otherElements["accent-2D6FB0"]
        // Swatch may surface as an other/image element depending on the run; fall back to any hittable match.
        let target = ocean.exists ? ocean : app.descendants(matching: .any).matching(identifier: "accent-2D6FB0").firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 5), "preset accent swatch should exist in Settings")
        target.tap()
        // No crash + Settings still up.
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
    }
```

- [ ] **Step 5: Run the UI smoke test**

Run: `xcodebuild test -scheme DailyTodo -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath build -only-testing:DailyTodoUITests/TaskFlowUITests/testAccentSwatchSelectable`
Expected: PASS. If the swatch isn't hittable as tapped, adjust the query to `.images`/`.buttons` matching the same identifier — keep the identifier `accent-2D6FB0`.

- [ ] **Step 6: Manual device/simulator verification**

Build, install, launch. In Settings → Accent: tap a preset and pick a custom color. Confirm the header buttons, checkboxes, Add FAB, and Go Live tint update immediately; background a widget and confirm it recolors; start a Live Activity and confirm it recolors. Relaunch — choice persists. Fresh install (erase app) looks like today's brick.

- [ ] **Step 7: Commit**

```bash
git add DailyTodo/Views/SettingsView.swift DailyTodoUITests/TaskFlowUITests.swift DailyTodo.xcodeproj/project.pbxproj
git commit -m "Add accent color picker (presets + custom) to Settings"
```

---

## Self-Review

**Spec coverage:**
- ThemeStore in App Group, default brick, presets → Task 1. ✓
- `brand`/`brandDark`/`brandTint` accent-derived; UIColor/Color helpers → Task 2. ✓
- Root `@AppStorage` repaint → Task 3. ✓
- Settings swatches + custom ColorPicker + footer/preview; `Surfaces.reload()` + `live.refresh()` → Task 4. ✓
- Cross-process to widget/LA → via existing read-fresh + Task 4 refreshes. ✓
- iOS 17 target preserved; new files via xcodegen → Global Constraints + Task 1/2 steps. ✓
- Unit tests (hex round-trip, malformed fallback, derived shades) → Tasks 1–2. ✓

**Placeholder scan:** None — every code step is complete.

**Type consistency:** `ThemeStore.accentHex`/`hexValue`/`normalizedHex`/`presets`/`accentKey`/`defaultAccentHex` defined in Task 1 and consumed verbatim in Tasks 2–4. `Color.toHex()` / `UIColor.adjustingBrightness`/`blended` defined in Task 2, consumed in Task 4's `accentBinding`. `setAccent(_:)`/`accentBinding` defined and consumed within Task 4. `Surfaces.reload()` and `LiveActivityController.refresh()` are existing. ✓

> A live preview "tile" from the spec is satisfied by the in-place recolor (the whole Settings screen + swatches reflect the choice instantly); no separate preview widget is needed. If desired later it's a trivial addition.
