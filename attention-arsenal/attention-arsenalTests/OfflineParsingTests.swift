//
//  OfflineParsingTests.swift
//  attention-arsenalTests
//
//  Covers the paths that used to fail silently: Siri when the OpenAI call errors out
//  (exhausted quota, no network, timeout), and monthly reminders losing every selected
//  day but the first on the round trip through Core Data.
//

import Testing
import Foundation
import CoreData
@testable import attention_arsenal

@Suite("Offline Siri parsing", .serialized)
struct SiriFallbackTests {

    @Test("a spoken day and time becomes a one-time reminder at that moment")
    func explicitDateTimeBecomesOneTime() throws {
        let parsed = SiriArsenalParser.shared.createFallback(from: "remind me to call the dentist tomorrow at 3pm")

        #expect(parsed.intervalConfig.type == .oneTime)
        let target = try #require(parsed.intervalConfig.targetDate)
        #expect(target > Date())
        #expect(Calendar.current.component(.hour, from: target) == 15)
        // The date phrase and the "remind me to" scaffolding belong in the schedule, not the title.
        #expect(!parsed.title.lowercased().contains("remind me"))
        #expect(!parsed.title.lowercased().contains("tomorrow"))
        #expect(parsed.title.contains("dentist"))
    }

    @Test("a recurring phrase stays recurring and keeps the spoken time")
    func recurringPhraseKeepsItsCadence() {
        let parsed = SiriArsenalParser.shared.createFallback(from: "remind me to take my medication every day at 9am")

        #expect(parsed.intervalConfig.type == .daily)
        #expect(parsed.intervalConfig.hour == 9)
        #expect(parsed.intervalConfig.minute == 0)
        #expect(parsed.title.lowercased().contains("medication"))
    }

    @Test("weekly and monthly phrases map to their own interval types")
    func weeklyAndMonthlyPhrases() {
        #expect(SiriArsenalParser.shared.createFallback(from: "water the plants every week").intervalConfig.type == .weekly)
        #expect(SiriArsenalParser.shared.createFallback(from: "pay rent monthly").intervalConfig.type == .monthly)
    }

    @Test("a command with no date still produces a firing reminder, never .none")
    func noDateStillSchedules() {
        let parsed = SiriArsenalParser.shared.createFallback(from: "call mom")
        #expect(parsed.intervalConfig.type != .none)
        #expect(!parsed.title.isEmpty)
    }
}

@Suite("Monthly day persistence", .serialized)
struct MonthlyPersistenceTests {

    @Test("every selected day of the month survives a save and reload")
    func multipleMonthDaysRoundTrip() {
        let context = PersistenceController.preview.container.viewContext
        let arsenal = Arsenal(context: context)
        arsenal.title = "Rent and review"
        arsenal.createdDate = Date()

        var config = IntervalConfiguration(type: .monthly, value: 1, hour: 9, minute: 0)
        config.monthDays = MonthDaysBitmask()
        config.monthDays.set(5, selected: true)
        config.monthDays.set(20, selected: true)
        config.apply(to: arsenal)

        // Reading the arsenal back used to collapse this to [5] — notificationDayOfMonth only
        // ever holds the first day, and it was being preferred over the full bitmask.
        let reloaded = IntervalConfiguration(from: arsenal)
        #expect(reloaded.monthDays.selectedDays == [5, 20])
    }

    @Test("an arsenal written by a pre-bitmask version still reads its single day")
    func legacySingleDayStillReads() {
        let context = PersistenceController.preview.container.viewContext
        let arsenal = Arsenal(context: context)
        arsenal.title = "Legacy monthly"
        arsenal.createdDate = Date()
        arsenal.intervalType = IntervalType.monthly.rawValue
        arsenal.intervalValue = 1
        arsenal.notificationInterval = 0      // no bitmask was written back then
        arsenal.notificationDayOfMonth = 12

        #expect(IntervalConfiguration(from: arsenal).monthDays.selectedDays == [12])
    }
}

@Suite("Spoken time on AI-parsed reminders", .serialized)
struct SpokenTimeTests {

    @Test("a daily reminder keeps the hour the user said, not the 9am default")
    func dailyKeepsSpokenHour() {
        let config = SiriArsenalParser.applySpokenTime(
            to: .defaultDaily,
            from: "remind me to take my medication every day at 6pm"
        )
        #expect(config.type == .daily)
        #expect(config.hour == 18)
        #expect(config.minute == 0)
    }

    @Test("a weekly reminder takes both the named weekday and the spoken time")
    func weeklyTakesNamedWeekday() {
        let config = SiriArsenalParser.applySpokenTime(
            to: .defaultWeekly,
            from: "water the plants every week on Saturday at 7am"
        )
        #expect(config.type == .weekly)
        #expect(config.hour == 7)
        #expect(config.days.selectedDays == [.saturday])
    }

    @Test("a bare daily phrase never rewrites the weekly day set to today")
    func unnamedWeekdayLeavesDaysAlone() {
        var weekly = IntervalConfiguration.defaultWeekly
        var days = DaysBitmask()
        days.set(.monday, selected: true)
        days.set(.thursday, selected: true)
        weekly.days = days

        let config = SiriArsenalParser.applySpokenTime(to: weekly, from: "stretch at 8pm")
        #expect(config.hour == 20)
        #expect(config.days.selectedDays == [.monday, .thursday])
    }

    @Test("intervals with no time component are left untouched")
    func nonTimedIntervalsUnchanged() {
        let hourly = IntervalConfiguration(type: .hours, value: 2)
        let config = SiriArsenalParser.applySpokenTime(to: hourly, from: "check the oven every 2 hours")
        #expect(config.type == .hours)
        #expect(config.value == 2)
    }
}
