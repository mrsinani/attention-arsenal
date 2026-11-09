import Testing
import Foundation
@testable import attention_arsenal

@Suite("QuietHours")
struct QuietHoursTests {
    private let calendar = Calendar(identifier: .gregorian)
    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 1) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 4, day: day, hour: hour, minute: minute))!
    }

    @Test func overnightWindowWrapsMidnight() {
        let quiet = QuietHours(start: 22 * 60, end: 8 * 60)
        #expect(quiet.contains(at(23), calendar: calendar))
        #expect(quiet.contains(at(2), calendar: calendar))
        #expect(quiet.contains(at(22), calendar: calendar))
        #expect(!quiet.contains(at(8), calendar: calendar))      // end is exclusive
        #expect(!quiet.contains(at(21, 59), calendar: calendar))
    }

    @Test func sameDayWindow() {
        let quiet = QuietHours(start: 13 * 60, end: 14 * 60)
        #expect(quiet.contains(at(13, 30), calendar: calendar))
        #expect(!quiet.contains(at(14), calendar: calendar))
        #expect(!quiet.contains(at(23), calendar: calendar))
    }

    @Test func endDateIsNextMorning() {
        let quiet = QuietHours(start: 22 * 60, end: 8 * 60)
        #expect(quiet.endDate(after: at(23), calendar: calendar) == at(8, day: 2))
        #expect(quiet.endDate(after: at(3, day: 2), calendar: calendar) == at(8, day: 2))
    }
}
