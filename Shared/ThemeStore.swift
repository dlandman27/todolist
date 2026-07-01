import SwiftUI
import UIKit

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

    // MARK: Background (app-only; Spec 2)
    static let backgroundKindKey = "themeBackgroundKind"
    static let backgroundColorKey = "themeBackgroundColorHex"
    static let gradientTopKey = "themeGradientTopHex"
    static let gradientBottomKey = "themeGradientBottomHex"
    static let backgroundPhotoTokenKey = "themeBackgroundPhotoToken"

    static let defaultBackgroundColorHex = "20272E"  // calm slate
    static let defaultGradientTopHex = "3A3897"      // indigo
    static let defaultGradientBottomHex = "8E2D6B"   // plum

    /// Curated two-stop background gradients (top → bottom). A mix of deep tones
    /// (most legible) and brighter/pastel picks. Very light ones trade some contrast
    /// for fun — the scrim softens them.
    static let gradientPresets: [GradientPreset] = [
        // Deep / moody
        GradientPreset(top: "3A3897", bottom: "8E2D6B"), // Indigo · Plum (default)
        GradientPreset(top: "2C3E50", bottom: "4CA1AF"), // Steel · Teal
        GradientPreset(top: "0F2027", bottom: "2C5364"), // Deep Ocean
        GradientPreset(top: "42275A", bottom: "734B6D"), // Plum · Mauve
        GradientPreset(top: "134E5E", bottom: "3D7A5C"), // Pine · Sage
        GradientPreset(top: "4E0E1E", bottom: "B24C3B"), // Ember
        GradientPreset(top: "232526", bottom: "414345"), // Charcoal
        GradientPreset(top: "1A2980", bottom: "2A6E8F"), // Blue · Cyan
        GradientPreset(top: "6A2C70", bottom: "B33771"), // Berry
        GradientPreset(top: "2B1055", bottom: "7597DE"), // Night · Periwinkle
        // Vibrant
        GradientPreset(top: "FF6FD8", bottom: "3813C2"), // Miami
        GradientPreset(top: "7F00FF", bottom: "E100FF"), // Grape Soda
        GradientPreset(top: "FF9966", bottom: "FF5E62"), // Warm Sunset
        GradientPreset(top: "EB3349", bottom: "F45C43"), // Cherry
        GradientPreset(top: "43E97B", bottom: "38F9D7"), // Mint
        GradientPreset(top: "2980B9", bottom: "6DD5FA"), // Sky
        GradientPreset(top: "FFE259", bottom: "FFA751"), // Mango
        // Pastel / soft
        GradientPreset(top: "FBC2EB", bottom: "A6C1EE"), // Cotton Candy
        GradientPreset(top: "FF9A9E", bottom: "FECFEF"), // Bubblegum
        GradientPreset(top: "A1C4FD", bottom: "C2E9FB"), // Baby Blue
        GradientPreset(top: "D4FC79", bottom: "96E6A1"), // Honeydew
        GradientPreset(top: "F4C4F3", bottom: "FC67FA"), // Rose Petal
    ]

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
}

/// Live, observable mirror of the persisted accent, injected into the app's
/// environment so a change repaints every SwiftUI view that reads it immediately.
/// `ThemeStore` stays the persisted source of truth (and what the widget/Live
/// Activity read); this just drives in-app reactivity.
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

    /// The accent as a SwiftUI `Color` (reads `accentHex`, so it is observed).
    var accent: Color { Color(hex: ThemeStore.hexValue(accentHex)) }

    /// Persist the accent (for `Color.brand`, the widget, the Live Activity, and
    /// relaunches) and update the observed property so the app repaints live.
    func setAccent(_ hex: String) {
        let norm = ThemeStore.normalizedHex(hex) ?? ThemeStore.defaultAccentHex
        ThemeStore.accentHex = norm
        accentHex = norm
    }

    // MARK: Background

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
