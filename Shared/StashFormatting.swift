import Foundation

/// Formats a stashed task's return date as a quiet relative label.
enum StashFormatting {
    /// "Someday" when there's no return date (Never); otherwise "Back tomorrow" /
    /// "Back in N days" / "Back today" based on whole-day distance.
    static func returnLabel(for date: Date?, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let date else { return "Someday" }
        let start = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: start, to: target).day ?? 0
        switch days {
        case ..<1:  return "Back today"
        case 1:     return "Back tomorrow"
        default:    return "Back in \(days) days"
        }
    }
}
