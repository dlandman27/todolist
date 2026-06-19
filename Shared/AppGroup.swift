import Foundation

/// App Group used to share the SwiftData store between the app and the widget extension.
enum AppGroup {
    static let identifier = "group.com.dylanlandman.dailytodo"
}

/// The custom URL scheme used to deep-link into the app (e.g. from the widget's add button).
enum DeepLink {
    static let scheme = "dailytodo"
    static let addHost = "add"
    static let addURL = URL(string: "\(scheme)://\(addHost)")!
}
