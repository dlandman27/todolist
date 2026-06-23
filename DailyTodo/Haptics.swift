import UIKit

/// Centralized haptic feedback, gated behind a single user-facing toggle.
///
/// The on/off state lives in `UserDefaults` under ``defaultsKey`` so both SwiftUI
/// views (via `@AppStorage`) and plain model code (toggle/commit/delete) read the
/// same flag. Defaults to on when unset.
enum Haptics {
    /// `@AppStorage` key shared with the settings toggle.
    static let defaultsKey = "hapticsEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }

    /// A physical tap — use for button presses and adding rows.
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    /// Success / warning / error notification — use for completing or deleting.
    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    /// Light selection tick — use for discrete state changes.
    static func selection() {
        guard isEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
