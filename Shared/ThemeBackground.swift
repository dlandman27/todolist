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
                    // Color.clear is the sizer (fills the container); the image fills it
                    // via scaledToFill and is clipped, so it can't overflow and blow up
                    // the enclosing layout (which would push the app's content off-screen).
                    Color.clear
                        .overlay {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        }
                        .clipped()
                } else {
                    Color.appBackground
                }
            }
            Color.appBackground.opacity(theme.backgroundKind.scrimOpacity)
        }
        .ignoresSafeArea()
    }
}
