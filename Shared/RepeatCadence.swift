import Foundation

/// How often a repeat rule adds a task. Weekly or monthly only — day-granular, no times.
/// Weekdays use Calendar numbering (1 = Sunday … 7 = Saturday); month days are 1…31.
enum RepeatCadence: Codable, Equatable {
    case weekly(Set<Int>)     // set of weekdays; non-empty
    case monthly(Set<Int>)    // set of days-of-month; non-empty

    /// Fixed English short weekday names, indexed by Calendar weekday (1 = Sun).
    /// Deliberately not locale-derived, so `summary()` is deterministic and testable.
    static let weekdayShortNames = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    /// Whether this cadence fires on the given day (weekday in the set for weekly,
    /// day-of-month in the set for monthly). A monthly day the month lacks (e.g. 31 in
    /// February) simply never matches that month.
    func isScheduled(on day: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .weekly(let days):  return days.contains(calendar.component(.weekday, from: day))
        case .monthly(let days): return days.contains(calendar.component(.day, from: day))
        }
    }

    /// A short human summary, e.g. "Mon · Wed · Fri", "1st of the month", "1st · 15th".
    func summary() -> String {
        switch self {
        case .weekly(let days):
            return days.sorted().map { Self.weekdayShortNames[$0] }.joined(separator: " · ")
        case .monthly(let days):
            let sorted = days.sorted()
            if sorted.count == 1 { return "\(Self.ordinal(sorted[0])) of the month" }
            return sorted.map(Self.ordinal).joined(separator: " · ")
        }
    }

    /// "1st", "2nd", "3rd", "21st", … for a day-of-month.
    static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 100, n % 10) {
        case (11, _), (12, _), (13, _): suffix = "th"
        case (_, 1): suffix = "st"
        case (_, 2): suffix = "nd"
        case (_, 3): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }

    // MARK: - Persistence (JSON string, stored on RepeatRule)

    func encoded() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(from string: String) -> RepeatCadence? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(RepeatCadence.self, from: data)
    }
}
