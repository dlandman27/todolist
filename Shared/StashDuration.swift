import Foundation

/// The three ways to stash a task. Returns are local-midnight, date-boundary based.
enum StashDuration: CaseIterable, Identifiable {
    case tomorrow
    case nextWeek
    case never

    var id: Self { self }

    var label: String {
        switch self {
        case .tomorrow: return "Tomorrow"
        case .nextWeek: return "Next week"
        case .never:    return "Never"
        }
    }

    /// The auto-return instant (local midnight of the target day), or `nil` for Never.
    func returnDate(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        let startOfToday = calendar.startOfDay(for: now)
        switch self {
        case .tomorrow: return calendar.date(byAdding: .day, value: 1, to: startOfToday)
        case .nextWeek: return calendar.date(byAdding: .day, value: 7, to: startOfToday)
        case .never:    return nil
        }
    }
}
