import SwiftUI
import UIKit

/// App color palette. Brick-red brand (#BC4749) on a soft ground, with a warm
/// dark variant for each surface/text color so the app theme picker (Light /
/// Dark / System) actually changes the appearance.
private func rgb(_ hex: UInt32) -> UIColor {
    UIColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

/// A color that resolves to `light`/`dark` based on the active interface style.
private func dynamic(light: UInt32, dark: UInt32) -> UIColor {
    UIColor { $0.userInterfaceStyle == .dark ? rgb(dark) : rgb(light) }
}

extension UIColor {
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
    // MARK: Surfaces
    /// App-wide background: a near-neutral base leaned ever so slightly toward
    /// the current accent. The old hardcoded values (FFF9FB / 171113) were
    /// exactly this recipe baked in for Brick — ~3.5% tint in light, ~5% in
    /// dark — so the default accent still renders (near) identically, and any
    /// other accent warms/cools the background to match it.
    static let appBackgroundColor = UIColor { trait in
        rgb(ThemeStore.tintedBackgroundHex(
            accentHex: ThemeStore.accentHex,
            dark: trait.userInterfaceStyle == .dark
        ))
    }
    static let appSurfaceColor = dynamic(light: 0xFFFFFF, dark: 0x261E20)
    // MARK: Text
    static let appTextPrimary = dynamic(light: 0x2A1E1F, dark: 0xF5ECEE)
    static let appTextSecondary = dynamic(light: 0x93787B, dark: 0xB39DA0)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    // MARK: Brand

    /// Primary brand/accent color (user-customizable via ThemeStore).
    static var brand: Color { Color(uiColor: .appBrand) }
    /// Darker accent shade for pressed / emphasis states.
    static var brandDark: Color { Color(uiColor: .appBrandDark) }
    /// Soft accent wash for subtle fills and selected rows.
    static var brandTint: Color { Color(uiColor: .appBrandTint) }

    /// Muted sage-teal accent that marks the stash — complementary to the brand red and
    /// calm, reading as "set aside." Light text sits on it. Hex #5C8A7D.
    static let stashAccent = Color(hex: 0x5C8A7D)

    // MARK: Surfaces

    /// App-wide background.
    static let appBackground = Color(uiColor: .appBackgroundColor)
    /// Elevated surface for rows and cards.
    static let appSurface = Color(uiColor: .appSurfaceColor)

    // MARK: Text

    /// Primary text, a warm near-black (light) / near-white (dark).
    static let textPrimary = Color(uiColor: .appTextPrimary)
    /// Secondary text, a muted mauve-gray.
    static let textSecondary = Color(uiColor: .appTextSecondary)
}

extension Animation {
    /// Shared spring for the app's micro-interactions: gentle, no bounce — the
    /// single curve every add / complete / delete / reorder reuses for coherence.
    static let appMotion = Animation.smooth(duration: 0.3)
}

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

extension View {
    /// Wraps the view in a Liquid Glass capsule on iOS 26+, falling back to a
    /// tinted/material capsule on older systems. `tinted` brand-tints the active state.
    @ViewBuilder
    func glassCapsule(tinted: Bool) -> some View {
        if #available(iOS 26.0, *) {
            if tinted {
                self.glassEffect(.regular.tint(Color.brand.opacity(0.25)).interactive(), in: .capsule)
            } else {
                self.glassEffect(.regular.interactive(), in: .capsule)
            }
        } else {
            self.background(
                Capsule().fill(tinted ? AnyShapeStyle(Color.brandTint) : AnyShapeStyle(.ultraThinMaterial))
            )
        }
    }
}
