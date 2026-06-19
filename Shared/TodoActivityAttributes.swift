import ActivityKit
import Foundation

/// A task as carried inside the Live Activity (decoupled from SwiftData so it's Codable).
struct LiveTask: Codable, Hashable, Identifiable {
    var id: UUID
    var title: String
    var done: Bool
}

/// The Live Activity for the one list. No static attributes — there's only ever one.
struct TodoActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var tasks: [LiveTask]
        var openCount: Int { tasks.filter { !$0.done }.count }
    }
}
