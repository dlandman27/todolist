# Theming 2/2 — Custom Backgrounds — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users set the app's main background to a solid color, gradient, or photo, with a legibility scrim, managed on the Customize page — app-only, defaulting to today's flat background.

**Architecture:** Extend `ThemeStore` with background config (App Group defaults + a downscaled photo file) and `ThemeModel` with observed background state. A new `ThemeBackground` view renders the chosen background + an adaptive scrim and replaces the base `Color.appBackground` on the list and stash surfaces. `CustomizeView` gains a Background section (kind picker, color/gradient pickers, `PhotosPicker`).

**Tech Stack:** Swift, SwiftUI, PhotosUI, SwiftData. XcodeGen (`project.yml`) → builds verified in Xcode by the user.

## Global Constraints

- App deployment target **iOS 17.0**.
- Builds on Spec 1: `ThemeStore`, `ThemeModel` (`@Observable`, injected at root via `DailyTodoApp`), `CustomizeView`, `Color(hex:)`, `Color.toHex()`, `ThemeStore.normalizedHex`/`hexValue`.
- **App-only:** no widget/Live Activity/Control Center changes; no `Surfaces.reload()` needed for background changes.
- Default `backgroundKind` is **`.none`** (today's `appBackground`); clean install looks unchanged.
- New files under globbed folders (`Shared/`, `DailyTodoTests/`) need **`xcodegen generate`** to enter the project. (The user builds in Xcode; the agent only regenerates + commits.)

---

### Task 1: `BackgroundKind` + scrim + `ThemeStore` background config

Pure, testable enum + storage.

**Files:**
- Create: `Shared/ThemeBackground.swift` (enum + scrim here; the View is added in Task 3)
- Modify: `Shared/ThemeStore.swift` (background keys + accessors)
- Create: `DailyTodoTests/ThemeBackgroundTests.swift`

**Interfaces:**
- Consumes: `AppGroup.defaults`, `ThemeStore.normalizedHex` (existing).
- Produces:
  - `enum BackgroundKind: String, CaseIterable, Identifiable { case none, solid, gradient, photo }` with `label: String`, `scrimOpacity: Double`, `static func from(_ raw: String?) -> BackgroundKind`.
  - `ThemeStore.backgroundKind: BackgroundKind` (get/set)
  - `ThemeStore.backgroundColorHex: String`, `.gradientTopHex: String`, `.gradientBottomHex: String` (get/set, validated)
  - `ThemeStore.backgroundPhotoToken: String?` (get/set)
  - `ThemeStore.backgroundPhotoURL: URL?`
  - default hex constants.

- [ ] **Step 1: Write the failing test**

Create `DailyTodoTests/ThemeBackgroundTests.swift`:

```swift
import XCTest
@testable import DailyTodo

final class ThemeBackgroundTests: XCTestCase {

    func testKindRawRoundTrips() {
        for kind in BackgroundKind.allCases {
            XCTAssertEqual(BackgroundKind.from(kind.rawValue), kind)
        }
    }

    func testUnknownKindFallsBackToNone() {
        XCTAssertEqual(BackgroundKind.from("wallpaper"), .none)
        XCTAssertEqual(BackgroundKind.from(nil), .none)
    }

    func testScrimIsZeroForNoneAndSolid() {
        XCTAssertEqual(BackgroundKind.none.scrimOpacity, 0)
        XCTAssertEqual(BackgroundKind.solid.scrimOpacity, 0)
    }

    func testPhotoScrimIsStrongerThanGradient() {
        XCTAssertGreaterThan(BackgroundKind.photo.scrimOpacity, BackgroundKind.gradient.scrimOpacity)
        XCTAssertGreaterThan(BackgroundKind.gradient.scrimOpacity, 0)
    }
}
```

- [ ] **Step 2: Create the enum source**

Create `Shared/ThemeBackground.swift`:

```swift
import SwiftUI

/// What the app's main background is filled with. `none` = today's flat color.
enum BackgroundKind: String, CaseIterable, Identifiable {
    case none, solid, gradient, photo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "None"
        case .solid: "Color"
        case .gradient: "Gradient"
        case .photo: "Photo"
        }
    }

    /// Opacity of the `appBackground` veil drawn over the background to keep text
    /// legible. Busier backgrounds get a stronger veil; a solid color is left as-is.
    var scrimOpacity: Double {
        switch self {
        case .none, .solid: 0
        case .gradient: 0.10
        case .photo: 0.40
        }
    }

    /// Parse a stored raw value, defaulting to `.none` for missing/unknown.
    static func from(_ raw: String?) -> BackgroundKind {
        guard let raw, let kind = BackgroundKind(rawValue: raw) else { return .none }
        return kind
    }
}
```

- [ ] **Step 3: Add background config to `ThemeStore`**

In `Shared/ThemeStore.swift`, inside `enum ThemeStore`, add after the accent members:

```swift
    // MARK: Background (app-only; Spec 2)
    static let backgroundKindKey = "themeBackgroundKind"
    static let backgroundColorKey = "themeBackgroundColorHex"
    static let gradientTopKey = "themeGradientTopHex"
    static let gradientBottomKey = "themeGradientBottomHex"
    static let backgroundPhotoTokenKey = "themeBackgroundPhotoToken"

    static let defaultBackgroundColorHex = "20272E"  // calm slate
    static let defaultGradientTopHex = "3A3897"      // indigo
    static let defaultGradientBottomHex = "8E2D6B"   // plum

    static var backgroundKind: BackgroundKind {
        get { BackgroundKind.from(AppGroup.defaults?.string(forKey: backgroundKindKey)) }
        set { AppGroup.defaults?.set(newValue.rawValue, forKey: backgroundKindKey) }
    }

    static var backgroundColorHex: String {
        get { normalizedHex(AppGroup.defaults?.string(forKey: backgroundColorKey)) ?? defaultBackgroundColorHex }
        set { AppGroup.defaults?.set(normalizedHex(newValue) ?? defaultBackgroundColorHex, forKey: backgroundColorKey) }
    }

    static var gradientTopHex: String {
        get { normalizedHex(AppGroup.defaults?.string(forKey: gradientTopKey)) ?? defaultGradientTopHex }
        set { AppGroup.defaults?.set(normalizedHex(newValue) ?? defaultGradientTopHex, forKey: gradientTopKey) }
    }

    static var gradientBottomHex: String {
        get { normalizedHex(AppGroup.defaults?.string(forKey: gradientBottomKey)) ?? defaultGradientBottomHex }
        set { AppGroup.defaults?.set(normalizedHex(newValue) ?? defaultGradientBottomHex, forKey: gradientBottomKey) }
    }

    static var backgroundPhotoToken: String? {
        get { AppGroup.defaults?.string(forKey: backgroundPhotoTokenKey) }
        set { AppGroup.defaults?.set(newValue, forKey: backgroundPhotoTokenKey) }
    }

    /// File holding the downscaled background photo, in the shared container.
    static var backgroundPhotoURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?
            .appendingPathComponent("background.jpg")
    }
```

- [ ] **Step 4: Regenerate + run the test (expect PASS)**

Run: `xcodegen generate`
Then (user builds, or agent if permitted): `xcodebuild test -scheme DailyTodo -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath build -only-testing:DailyTodoTests/ThemeBackgroundTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Shared/ThemeBackground.swift Shared/ThemeStore.swift DailyTodoTests/ThemeBackgroundTests.swift DailyTodo.xcodeproj/project.pbxproj
git commit -m "Add BackgroundKind + ThemeStore background config"
```

---

### Task 2: `ThemeModel` background state + photo handling

Observed background state so changes repaint live, plus photo downscale/save/load.

**Files:**
- Modify: `Shared/ThemeStore.swift` (the `ThemeModel` class)

**Interfaces:**
- Consumes: Task 1's `ThemeStore` background accessors + `BackgroundKind`.
- Produces, on `ThemeModel`:
  - `var backgroundKind: BackgroundKind`
  - `var backgroundColorHex: String`, `var gradientTopHex: String`, `var gradientBottomHex: String`
  - `var backgroundImage: UIImage?`
  - `func setBackgroundKind(_:)`, `func setSolid(_ hex: String)`, `func setGradient(top: String, bottom: String)`, `func setPhoto(_ data: Data)`, `func clearPhoto()`

- [ ] **Step 1: Extend `ThemeModel`**

In `Shared/ThemeStore.swift`, replace the `ThemeModel` body to add background state. Keep the existing accent members; add:

```swift
@Observable
final class ThemeModel {
    var accentHex: String
    var backgroundKind: BackgroundKind
    var backgroundColorHex: String
    var gradientTopHex: String
    var gradientBottomHex: String
    var backgroundImage: UIImage?

    init() {
        accentHex = ThemeStore.accentHex
        backgroundKind = ThemeStore.backgroundKind
        backgroundColorHex = ThemeStore.backgroundColorHex
        gradientTopHex = ThemeStore.gradientTopHex
        gradientBottomHex = ThemeStore.gradientBottomHex
        backgroundImage = nil
        if backgroundKind == .photo { backgroundImage = Self.loadPhoto() }
    }

    var accent: Color { Color(hex: ThemeStore.hexValue(accentHex)) }

    func setAccent(_ hex: String) {
        let norm = ThemeStore.normalizedHex(hex) ?? ThemeStore.defaultAccentHex
        ThemeStore.accentHex = norm
        accentHex = norm
    }

    func setBackgroundKind(_ kind: BackgroundKind) {
        ThemeStore.backgroundKind = kind
        backgroundKind = kind
        if kind == .photo, backgroundImage == nil { backgroundImage = Self.loadPhoto() }
    }

    func setSolid(_ hex: String) {
        let norm = ThemeStore.normalizedHex(hex) ?? ThemeStore.defaultBackgroundColorHex
        ThemeStore.backgroundColorHex = norm
        backgroundColorHex = norm
        setBackgroundKind(.solid)
    }

    func setGradient(top: String, bottom: String) {
        ThemeStore.gradientTopHex = top
        ThemeStore.gradientBottomHex = bottom
        gradientTopHex = ThemeStore.gradientTopHex
        gradientBottomHex = ThemeStore.gradientBottomHex
        setBackgroundKind(.gradient)
    }

    /// Downscale, persist to the shared container, and show the picked photo.
    func setPhoto(_ data: Data) {
        guard let image = UIImage(data: data) else { return }
        let scaled = Self.downscale(image, maxDimension: 1400)
        if let url = ThemeStore.backgroundPhotoURL,
           let jpeg = scaled.jpegData(compressionQuality: 0.85) {
            try? jpeg.write(to: url, options: .atomic)
        }
        ThemeStore.backgroundPhotoToken = ISO8601DateFormatter().string(from: Date())
        backgroundImage = scaled
        setBackgroundKind(.photo)
    }

    func clearPhoto() {
        if let url = ThemeStore.backgroundPhotoURL { try? FileManager.default.removeItem(at: url) }
        ThemeStore.backgroundPhotoToken = nil
        backgroundImage = nil
        setBackgroundKind(.none)
    }

    private static func loadPhoto() -> UIImage? {
        guard let url = ThemeStore.backgroundPhotoURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Aspect-fit downscale so the longest side is `maxDimension` (no upscaling).
    private static func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
```

> Note: `ISO8601DateFormatter()` is allowed here (runtime app code, not a workflow script).

- [ ] **Step 2: Build to verify it compiles**

(User in Xcode, or:) `xcodebuild -scheme DailyTodo -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath build build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Shared/ThemeStore.swift
git commit -m "Add background state + photo save/load/downscale to ThemeModel"
```

---

### Task 3: `ThemeBackground` view + apply to list & stash

**Files:**
- Modify: `Shared/ThemeBackground.swift` (add the View)
- Modify: `DailyTodo/Views/ListView.swift`
- Modify: `DailyTodo/Views/StashSheet.swift`

**Interfaces:**
- Consumes: `ThemeModel` (env), `BackgroundKind.scrimOpacity`, `ThemeStore.hexValue`, `Color(hex:)`.
- Produces: `struct ThemeBackground: View`.

- [ ] **Step 1: Add the view**

Append to `Shared/ThemeBackground.swift`:

```swift
/// The app's main background: the user's chosen fill (color/gradient/photo) with a
/// legibility scrim over it, or the flat `appBackground` when kind is `.none`.
/// Reads `ThemeModel` from the environment so it repaints live.
struct ThemeBackground: View {
    @Environment(ThemeModel.self) private var theme

    var body: some View {
        ZStack {
            switch theme.backgroundKind {
            case .none:
                Color.appBackground
            case .solid:
                Color(hex: ThemeStore.hexValue(theme.backgroundColorHex))
            case .gradient:
                LinearGradient(
                    colors: [
                        Color(hex: ThemeStore.hexValue(theme.gradientTopHex)),
                        Color(hex: ThemeStore.hexValue(theme.gradientBottomHex)),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            case .photo:
                if let image = theme.backgroundImage {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color.appBackground
                }
            }
            Color.appBackground.opacity(theme.backgroundKind.scrimOpacity)
        }
        .ignoresSafeArea()
    }
}
```

- [ ] **Step 2: Use it on the main list**

In `DailyTodo/Views/ListView.swift`, replace the base background in the main `ZStack`:

```swift
                Color.appBackground
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    // Tapping empty chrome (header, sides) only dismisses an active edit —
                    // it must NOT add a task. Adding is handled by the explicit areas below.
                    .onTapGesture { dismissEditing() }
```

with:

```swift
                ThemeBackground()
                    .contentShape(Rectangle())
                    // Tapping empty chrome (header, sides) only dismisses an active edit —
                    // it must NOT add a task. Adding is handled by the explicit areas below.
                    .onTapGesture { dismissEditing() }
```

- [ ] **Step 3: Use it on the stash, and pass the theme into the sheet**

In `DailyTodo/Views/StashSheet.swift`, replace `Color.appBackground.ignoresSafeArea()` (the first child of the body `ZStack`) with `ThemeBackground()`.

Then in `DailyTodo/Views/ListView.swift`, ensure the sheet inherits the model — change the stash sheet presentation:

```swift
        .sheet(isPresented: $showStash) {
            StashSheet()
                .environment(live)
        }
```

to:

```swift
        .sheet(isPresented: $showStash) {
            StashSheet()
                .environment(live)
                .environment(theme)
        }
```

(`theme` is the `@Environment(ThemeModel.self)` already on `ListView` from Spec 1.)

- [ ] **Step 4: Build to verify it compiles**

Expected: BUILD SUCCEEDED. (Default kind `.none` → list/stash look exactly as today.)

- [ ] **Step 5: Commit**

```bash
git add Shared/ThemeBackground.swift DailyTodo/Views/ListView.swift DailyTodo/Views/StashSheet.swift
git commit -m "Render ThemeBackground on the list and stash surfaces"
```

---

### Task 4: Background section in `CustomizeView` (+ photo picker, preview)

**Files:**
- Modify: `DailyTodo/Views/CustomizeView.swift`

**Interfaces:**
- Consumes: `ThemeModel` setters (Task 2), `ThemeBackground` (Task 3), `BackgroundKind`, `PhotosUI`.

- [ ] **Step 1: Add PhotosUI + photo-pick state**

At the top of `DailyTodo/Views/CustomizeView.swift`:

```swift
import SwiftUI
import PhotosUI
```

Add state to `CustomizeView`:

```swift
    @State private var photoItem: PhotosPickerItem?
```

- [ ] **Step 2: Render the preview over the background**

Replace the `previewTile`'s outer container so it sits on the live background. Change the `Section { previewTile … }` to:

```swift
                Section {
                    previewTile
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background {
                            ThemeBackground()
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                        .listRowBackground(Color.appSurface)
                } header: {
                    Text("Preview")
                }
```

- [ ] **Step 3: Add the Background section**

After the Accent `Section`, add:

```swift
                Section {
                    Picker("Background", selection: backgroundKindBinding) {
                        ForEach(BackgroundKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.appSurface)

                    switch theme.backgroundKind {
                    case .none:
                        EmptyView()
                    case .solid:
                        ColorPicker(selection: solidBinding, supportsOpacity: false) {
                            Label("Color", systemImage: "paintpalette")
                                .foregroundStyle(Color.textPrimary)
                        }
                        .listRowBackground(Color.appSurface)
                    case .gradient:
                        ColorPicker(selection: gradientTopBinding, supportsOpacity: false) {
                            Label("Top", systemImage: "arrow.up").foregroundStyle(Color.textPrimary)
                        }
                        .listRowBackground(Color.appSurface)
                        ColorPicker(selection: gradientBottomBinding, supportsOpacity: false) {
                            Label("Bottom", systemImage: "arrow.down").foregroundStyle(Color.textPrimary)
                        }
                        .listRowBackground(Color.appSurface)
                    case .photo:
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label(theme.backgroundImage == nil ? "Choose Photo" : "Change Photo",
                                  systemImage: "photo")
                                .foregroundStyle(Color.brand)
                        }
                        .listRowBackground(Color.appSurface)
                        if theme.backgroundImage != nil {
                            Button(role: .destructive) { theme.clearPhoto() } label: {
                                Label("Remove Photo", systemImage: "trash")
                            }
                            .listRowBackground(Color.appSurface)
                        }
                    }
                } header: {
                    Text("Background")
                } footer: {
                    Text("Applies to the main list and stash. Photos stay on your device.")
                }
                .onChange(of: photoItem) { _, item in
                    guard let item else { return }
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            theme.setPhoto(data)
                        }
                    }
                }
```

- [ ] **Step 4: Add the bindings**

Add to `CustomizeView`:

```swift
    private var backgroundKindBinding: Binding<BackgroundKind> {
        Binding(get: { theme.backgroundKind }, set: { theme.setBackgroundKind($0) })
    }
    private var solidBinding: Binding<Color> {
        Binding(get: { Color(hex: ThemeStore.hexValue(theme.backgroundColorHex)) },
                set: { theme.setSolid($0.toHex()) })
    }
    private var gradientTopBinding: Binding<Color> {
        Binding(get: { Color(hex: ThemeStore.hexValue(theme.gradientTopHex)) },
                set: { theme.setGradient(top: $0.toHex(), bottom: theme.gradientBottomHex) })
    }
    private var gradientBottomBinding: Binding<Color> {
        Binding(get: { Color(hex: ThemeStore.hexValue(theme.gradientBottomHex)) },
                set: { theme.setGradient(top: theme.gradientTopHex, bottom: $0.toHex()) })
    }
```

- [ ] **Step 5: Build + manual verification**

Build (Xcode). On the Customize page: switch kinds; pick a solid color, a gradient (top/bottom), and a photo from the library. Confirm the preview tile and the main list + stash update and stay legible (esp. a busy photo). Relaunch persists. "Remove Photo" reverts to None. Forms (Settings/Customize) stay flat.

- [ ] **Step 6: Commit**

```bash
git add DailyTodo/Views/CustomizeView.swift
git commit -m "Add background controls (color/gradient/photo) to Customize"
```

---

## Self-Review

**Spec coverage:**
- `BackgroundKind` + config in `ThemeStore` → Task 1. ✓
- `ThemeModel` background state + photo downscale/save/load → Task 2. ✓
- `ThemeBackground` (fill + scrim) on list + stash → Task 3. ✓
- CustomizeView background section (kind/solid/gradient/photo) + preview over background → Task 4. ✓
- App-only (no widget/LA) → no `Surfaces.reload()` in any background setter. ✓
- Default `.none` = unchanged → `BackgroundKind.from` default + Task 3 note. ✓
- Photo perf (downscale, load once) → Task 2 `downscale`/`loadPhoto`, cached in `backgroundImage`. ✓
- Legibility scrim per kind → Task 1 `scrimOpacity`, Task 3 overlay. ✓
- iOS 17 target; new files via xcodegen → Global Constraints + Task 1 step. ✓

**Placeholder scan:** none — every step has complete code.

**Type consistency:** `BackgroundKind` (Task 1) used across 2–4. `ThemeStore.background*` accessors (Task 1) consumed by `ThemeModel` (Task 2). `ThemeModel.set{BackgroundKind,Solid,Gradient,Photo}`/`clearPhoto`/`backgroundImage` (Task 2) consumed by `ThemeBackground` (Task 3) and `CustomizeView` bindings (Task 4). `ThemeBackground` (Task 3) consumed by list/stash (Task 3) and the preview (Task 4). `theme` env object exists on `ListView`/`CustomizeView` from Spec 1. ✓
