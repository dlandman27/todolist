import SwiftUI

/// App color palette, built around the brick-red primary #BC4749 on a soft #FFF9FB ground.
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
    static let brand = Color(hex: 0xBC4749)
    /// Darker brand shade for pressed / emphasis states. Hex #97383A.
    static let brandDark = Color(hex: 0x97383A)
    /// Soft brand wash for subtle fills and selected rows. Hex #F6DEDF.
    static let brandTint = Color(hex: 0xF6DEDF)

    // MARK: Surfaces

    /// App-wide background. Hex #FFF9FB.
    static let appBackground = Color(hex: 0xFFF9FB)
    /// Elevated surface for rows and cards. Hex #FFFFFF.
    static let appSurface = Color(hex: 0xFFFFFF)

    // MARK: Text

    /// Primary text, a warm near-black. Hex #2A1E1F.
    static let textPrimary = Color(hex: 0x2A1E1F)
    /// Secondary text, a muted mauve-gray. Hex #93787B.
    static let textSecondary = Color(hex: 0x93787B)
}
