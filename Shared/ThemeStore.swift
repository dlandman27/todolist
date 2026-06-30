import SwiftUI

/// Single source of truth for the user's theme choices, backed by the App Group
/// defaults so the app, widget, and Live Activity all read the same values.
/// Spec 1 covers the accent color; Spec 2 extends this with backgrounds.
enum ThemeStore {
    static let accentKey = "themeAccentHex"
    /// Today's brick red — the default until the user picks something else.
    static let defaultAccentHex = "BC4749"

    /// Curated accent presets (6-digit hex, no `#`). First is the default brick.
    /// A broad spread that all read well on both light and dark surfaces.
    static let presets: [String] = [
        "BC4749", // Brick (default)
        "D7503B", // Red
        "E0723C", // Sunset
        "C99A2E", // Gold
        "7FA037", // Lime
        "3E7D5A", // Forest
        "2E9E83", // Teal
        "2BB0C4", // Cyan
        "4FA3D1", // Sky
        "2D6FB0", // Ocean
        "5B6CC9", // Indigo
        "7A4F9E", // Grape
        "A24FB0", // Purple
        "C84B8E", // Magenta
        "E0658F", // Pink
        "C84B6E", // Rose
        "8C5A3C", // Clay
        "5B6472", // Slate
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

/// Live, observable mirror of the persisted accent, injected into the app's
/// environment so a change repaints every SwiftUI view that reads it immediately.
/// `ThemeStore` stays the persisted source of truth (and what the widget/Live
/// Activity read); this just drives in-app reactivity.
@Observable
final class ThemeModel {
    var accentHex: String

    init() { accentHex = ThemeStore.accentHex }

    /// The accent as a SwiftUI `Color` (reads `accentHex`, so it is observed).
    var accent: Color { Color(hex: ThemeStore.hexValue(accentHex)) }

    /// Persist the accent (for `Color.brand`, the widget, the Live Activity, and
    /// relaunches) and update the observed property so the app repaints live.
    func setAccent(_ hex: String) {
        let norm = ThemeStore.normalizedHex(hex) ?? ThemeStore.defaultAccentHex
        ThemeStore.accentHex = norm
        accentHex = norm
    }
}
