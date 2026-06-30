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
