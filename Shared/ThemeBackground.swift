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

/// A named-less two-stop gradient preset (top → bottom hex, no `#`).
struct GradientPreset: Identifiable, Hashable {
    let top: String
    let bottom: String
    var id: String { "\(top)\(bottom)" }

    var gradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: ThemeStore.hexValue(top)), Color(hex: ThemeStore.hexValue(bottom))],
            startPoint: .top, endPoint: .bottom
        )
    }
}

/// Renders a background from explicit values (the user's chosen fill + a legibility
/// scrim, or flat `appBackground` when `.none`). Shared by the app and the widget —
/// the widget can't read `ThemeModel`, so it passes values from `ThemeStore` directly.
struct ThemeBackgroundContent: View {
    let kind: BackgroundKind
    let colorHex: String
    let gradientTop: String
    let gradientBottom: String
    let image: UIImage?
    /// Drives the accent-tinted `.none` fill (and the scrim). Passed explicitly —
    /// reading it through the observable ThemeModel is what makes the app
    /// repaint the instant the accent changes (Color.appBackground's dynamic
    /// provider resolves lazily and can lag until the next full redraw).
    let accentHex: String

    /// Near-neutral base leaned toward the accent — same recipe on all surfaces.
    private func tinted(dark: Bool) -> Color {
        Color(hex: ThemeStore.tintedBackgroundHex(accentHex: accentHex, dark: dark))
    }

    @Environment(\.colorScheme) private var colorScheme

    private var base: Color { tinted(dark: colorScheme == .dark) }

    var body: some View {
        ZStack {
            switch kind {
            case .none:
                base
            case .solid:
                Color(hex: ThemeStore.hexValue(colorHex))
            case .gradient:
                LinearGradient(
                    colors: [
                        Color(hex: ThemeStore.hexValue(gradientTop)),
                        Color(hex: ThemeStore.hexValue(gradientBottom)),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            case .photo:
                if let image {
                    // Color.clear is the sizer (fills the container); the image fills it
                    // via scaledToFill and is clipped, so it can't overflow and blow up
                    // the enclosing layout (which would push content off-screen).
                    Color.clear
                        .overlay {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        }
                        .clipped()
                } else {
                    base
                }
            }
            base.opacity(kind.scrimOpacity)
        }
    }
}

/// The app's main background: reads the live `ThemeModel` and fills the screen.
struct ThemeBackground: View {
    @Environment(ThemeModel.self) private var theme

    var body: some View {
        ThemeBackgroundContent(
            kind: theme.backgroundKind,
            colorHex: theme.backgroundColorHex,
            gradientTop: theme.gradientTopHex,
            gradientBottom: theme.gradientBottomHex,
            image: theme.backgroundImage,
            accentHex: theme.accentHex
        )
        .ignoresSafeArea()
    }
}
