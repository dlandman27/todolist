import Foundation

/// App Group used to share the SwiftData store between the app and the widget extension.
enum AppGroup {
    static let identifier = "group.com.dylanlandman.dailytodo"

    /// Shared defaults, readable from both the app and the widget extension.
    static let defaults = UserDefaults(suiteName: identifier)
}

/// The user-customizable list name, shared across the app, widget, and Live Activity.
enum ListSettings {
    static let nameKey = "listName"
    static let defaultName = "To-Do"
    /// Keeps the title from overflowing the header / Lock Screen.
    static let maxNameLength = 24

    /// Current list name, falling back to ``defaultName`` when unset or blank.
    static var name: String {
        let raw = AppGroup.defaults?.string(forKey: nameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty == false) ? raw! : defaultName
    }
}

/// The custom URL scheme used to deep-link into the app (e.g. from the widget's add
/// button or a Control Center control).
enum DeepLink {
    static let scheme = "dailytodo"
    static let addHost = "add"
    static let addURL = URL(string: "\(scheme)://\(addHost)")!
    static let stashHost = "stash"
    static let stashURL = URL(string: "\(scheme)://\(stashHost)")!
}
