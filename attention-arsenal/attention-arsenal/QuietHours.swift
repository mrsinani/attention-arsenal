import Foundation

/// A daily window (Settings → Quiet Hours) where repeating nudges are held back. Times are
/// minutes after midnight; a window with start > end wraps past midnight (22:00–08:00).
struct QuietHours: Equatable {
    static let enabledKey = "quietHoursEnabled"
    static let startKey = "quietHoursStart"
    static let endKey = "quietHoursEnd"
    static let defaultStart = 22 * 60
    static let defaultEnd = 8 * 60

    var start: Int
    var end: Int

    /// The user's window, or nil when quiet hours are off (or start == end, an empty window).
    static var current: QuietHours? {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: enabledKey) else { return nil }
        let start = defaults.object(forKey: startKey) as? Int ?? defaultStart
        let end = defaults.object(forKey: endKey) as? Int ?? defaultEnd
        return start == end ? nil : QuietHours(start: start, end: end)
    }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return start < end ? (minute >= start && minute < end) : (minute >= start || minute < end)
    }

    /// The next time quiet hours end, after `date`.
    func endDate(after date: Date, calendar: Calendar = .current) -> Date {
        let match = DateComponents(hour: end / 60, minute: end % 60, second: 0)
        return calendar.nextDate(after: date, matching: match, matchingPolicy: .nextTime) ?? date
    }

    /// "10:00 PM – 8:00 AM" in the user's locale.
    var displayText: String {
        let format = Date.FormatStyle(date: .omitted, time: .shortened)
        let midnight = Calendar.current.startOfDay(for: Date())
        let from = midnight.addingTimeInterval(TimeInterval(start * 60)).formatted(format)
        let to = midnight.addingTimeInterval(TimeInterval(end * 60)).formatted(format)
        return "\(from) – \(to)"
    }
}
