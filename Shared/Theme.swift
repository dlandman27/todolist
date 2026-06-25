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
    // MARK: Brand
    static let appBrand = rgb(0xBC4749)
    static let appBrandDark = rgb(0x97383A)
    static let appBrandTint = dynamic(light: 0xF6DEDF, dark: 0x4A2E30)
    // MARK: Surfaces
    static let appBackgroundColor = dynamic(light: 0xFFF9FB, dark: 0x171113)
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

    /// Primary brand color. Hex #BC4749.
    static let brand = Color(uiColor: .appBrand)
    /// Darker brand shade for pressed / emphasis states. Hex #97383A.
    static let brandDark = Color(uiColor: .appBrandDark)
    /// Soft brand wash for subtle fills and selected rows.
    static let brandTint = Color(uiColor: .appBrandTint)

    /// Warm gold accent that marks the stash — distinct from the brand red, and dark
    /// enough text sits on it in black. Hex #DDB967.
    static let stashAccent = Color(hex: 0xDDB967)

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
