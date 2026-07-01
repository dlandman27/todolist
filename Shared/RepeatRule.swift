import Foundation
import SwiftData

/// A standing rule that adds an ordinary task to the list on a weekly/monthly rhythm.
/// The tasks it spawns are independent `TaskItem`s; this rule is the only place the
/// "repeating" concept is persisted. CloudKit-backed — every property is defaulted.
@Model
final class RepeatRule {
    var id: UUID = UUID()
    /// The title given to tasks this rule spawns.
    var name: String = ""
    /// JSON-encoded `RepeatCadence`. `nil` until a cadence is set.
    var cadenceData: String? = nil
    var createdAt: Date = Date()
    /// Start-of-day of the last day this rule spawned a task, so it fires at most once
    /// per scheduled day and supports single missed-day catch-up. `nil` = never spawned.
    var lastSpawnedDay: Date? = nil

    init(
        id: UUID = UUID(),
        name: String = "",
        cadenceData: String? = nil,
        createdAt: Date = Date(),
        lastSpawnedDay: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.cadenceData = cadenceData
        self.createdAt = createdAt
        self.lastSpawnedDay = lastSpawnedDay
    }

    /// Typed view over `cadenceData`. Not persisted itself (computed).
    var cadence: RepeatCadence? {
        get { cadenceData.flatMap(RepeatCadence.decode) }
        set { cadenceData = newValue?.encoded() }
    }
}
