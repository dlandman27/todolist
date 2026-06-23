import SwiftUI

/// User-selectable color scheme, stored in `UserDefaults` under ``defaultsKey``.
/// Defaults to ``system`` (follow the device setting).
enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    /// `@AppStorage` key shared between the app root and the settings picker.
    static let defaultsKey = "appTheme"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `nil` lets the system decide; otherwise forces the chosen scheme.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
