import Foundation

enum RelativeDate {
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    /// Formats a date as "Today 3:15 PM", "Yesterday 5:22 PM", or "Mar 3, 2026".
    static func string(for date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today \(timeFormatter.string(from: date))"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday \(timeFormatter.string(from: date))"
        }
        return dateFormatter.string(from: date)
    }
}

extension Date {
    /// Convenience relative description used in the UI.
    var relativeDescription: String { RelativeDate.string(for: self) }
}
