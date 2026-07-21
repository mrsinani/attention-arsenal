//
//  NotificationManagerTests.swift
//  attention-arsenalTests
//
//  Regression tests for the reminder-scheduling bugs reported before 2026-07-21's
//  batching/deferred-start rework: notifications firing for the wrong arsenal, and
//  one-time/monthly reminders landing on the wrong date. These drive the REAL
//  production trigger-generation code (no parallel test-only logic to drift out of
//  sync — that's what broke the old NotificationTestView-based test mode) via an
//  injected clock (`NotificationManager.now`).
//

import Testing
import Foundation
import CoreData
import UserNotifications
@testable import attention_arsenal

@Suite("NotificationManager scheduling", .serialized)
struct NotificationManagerTests {

    /// `UNCalendarNotificationTrigger.nextTriggerDate()` computes relative to the REAL device
    /// clock, ignoring our injected `NotificationManager.now` — so it returns nil for any
    /// synthetic test date in the past relative to today. `dateComponents.date` is pure data
    /// (the trigger stores its own calendar + time zone), so it's clock-independent.
    private func fireDate(of trigger: UNNotificationTrigger) -> Date? {
        (trigger as? UNCalendarNotificationTrigger)?.dateComponents.date
    }

    private func makeArsenal(notificationStartDate: Date? = nil) -> Arsenal {
        let context = PersistenceController(inMemory: true).container.viewContext
        let arsenal = Arsenal(context: context)
        arsenal.title = "Test Arsenal"
        arsenal.createdDate = Date()
        arsenal.notificationStartDate = notificationStartDate
        return arsenal
    }

    // MARK: - Identifier collision: acting on arsenal p5 must not touch p50's notifications

    @Test("arsenal p5's base id does not match p50's or p500's notification identifiers")
    func identifierCollisionFixed() {
        let manager = NotificationManager.shared
        let baseId5 = "arsenal_x-coredata://STORE-UUID/Arsenal/p5"

        #expect(manager.belongsToArsenal("\(baseId5)_0", baseId: baseId5))
        #expect(manager.belongsToArsenal("\(baseId5)_12", baseId: baseId5))
        #expect(!manager.belongsToArsenal("arsenal_x-coredata://STORE-UUID/Arsenal/p50_0", baseId: baseId5))
        #expect(!manager.belongsToArsenal("arsenal_x-coredata://STORE-UUID/Arsenal/p500_3", baseId: baseId5))
        #expect(!manager.belongsToArsenal("arsenal_x-coredata://STORE-UUID/Arsenal/p59_1", baseId: baseId5))
    }

    // MARK: - "Halloween reminder in April": one-time trigger must keep its exact date

    @Test("one-time reminder fires on the configured date no matter when it was scheduled")
    func oneTimeReminderKeepsItsDate() throws {
        let calendar = Calendar.current
        let halloween = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 18, minute: 0))!
        let schedulingDay = calendar.date(from: DateComponents(year: 2026, month: 4, day: 1, hour: 9, minute: 0))!

        let previousClock = NotificationManager.now
        NotificationManager.now = { schedulingDay }
        defer { NotificationManager.now = previousClock }

        let manager = NotificationManager.shared
        let config = IntervalConfiguration(type: .oneTime, targetDate: halloween)
        let triggers = manager.createTriggers(for: config, batchSize: 1, earliestFire: schedulingDay, deferredStart: nil)

        let trigger = try #require(triggers.first)
        let firedDate = try #require(fireDate(of: trigger))
        let fired = calendar.dateComponents([.month, .day], from: firedDate)
        #expect(fired.month == 10)
        #expect(fired.day == 31)
    }

    // MARK: - Monthly day-31 must skip 30-day months instead of misfiring into them

    @Test("monthly reminder on day 31 skips April and lands on May 31")
    func monthlyDay31SkipsShortMonths() throws {
        let calendar = Calendar.current
        let scheduledFromApril = calendar.date(from: DateComponents(year: 2026, month: 4, day: 1, hour: 9, minute: 0))!

        let previousClock = NotificationManager.now
        NotificationManager.now = { scheduledFromApril }
        defer { NotificationManager.now = previousClock }

        let manager = NotificationManager.shared
        var config = IntervalConfiguration(type: .monthly, value: 1, hour: 9, minute: 0)
        config.monthDays = MonthDaysBitmask.day(31)

        let triggers = manager.createBatchedTriggers(
            for: config, batchSize: 1, continuingFrom: nil,
            earliestFire: scheduledFromApril, deferredStart: nil
        )

        let trigger = try #require(triggers.first)
        let firedDate = try #require(fireDate(of: trigger))
        let fired = calendar.dateComponents([.month, .day], from: firedDate)
        #expect(fired.month == 5)
        #expect(fired.day == 31)
    }

    // MARK: - Deferred start gate

    @Test("earliestFireDate honors a future deferred start")
    func deferredStartInFuture() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let future = now.addingTimeInterval(3600)

        let previousClock = NotificationManager.now
        NotificationManager.now = { now }
        defer { NotificationManager.now = previousClock }

        let manager = NotificationManager.shared
        let arsenal = makeArsenal(notificationStartDate: future)
        #expect(manager.earliestFireDate(for: arsenal) == future)
    }

    @Test("earliestFireDate falls back to now once a deferred start has passed")
    func deferredStartInPast() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let past = now.addingTimeInterval(-3600)

        let previousClock = NotificationManager.now
        NotificationManager.now = { now }
        defer { NotificationManager.now = previousClock }

        let manager = NotificationManager.shared
        let arsenal = makeArsenal(notificationStartDate: past)
        #expect(manager.earliestFireDate(for: arsenal) == now)
    }

    // MARK: - DST safety: a batched daily schedule must not drift off its configured hour.
    // Exercises the actual DST transition when the host's current time zone observes one on
    // this date; on a non-DST host it still verifies the hour never drifts, which is the
    // invariant that actually matters.

    @Test("daily batched triggers keep the configured hour across a DST boundary")
    func dailyBatchKeepsConfiguredHour() throws {
        let calendar = Calendar.current
        // 2026-03-06, two days before the US spring-forward on March 8.
        let beforeDST = calendar.date(from: DateComponents(year: 2026, month: 3, day: 6, hour: 9, minute: 0))!

        let previousClock = NotificationManager.now
        NotificationManager.now = { beforeDST }
        defer { NotificationManager.now = previousClock }

        let manager = NotificationManager.shared
        var config = IntervalConfiguration(type: .daily, hour: 9, minute: 0)
        config.days = .allDays

        let triggers = manager.createBatchedTriggers(
            for: config, batchSize: 6, continuingFrom: nil,
            earliestFire: beforeDST, deferredStart: beforeDST
        )

        #expect(triggers.count == 6)
        for trigger in triggers {
            let firedDate = try #require(fireDate(of: trigger))
            #expect(calendar.component(.hour, from: firedDate) == 9)
        }
    }

    // MARK: - Batch continuation: topping up must not duplicate or skip a fire

    @Test("hours batch continuation lands exactly one interval after the last pending fire")
    func hoursBatchContinuesWithoutGapOrOverlap() throws {
        // Whole-minute timestamp: triggers always zero out seconds when built, so a `now` with
        // a nonzero seconds component would make this assert against a moment that never
        // actually gets scheduled — an artifact of the test input, not of production behavior.
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 0, minute: 0, second: 0))!

        let previousClock = NotificationManager.now
        NotificationManager.now = { now }
        defer { NotificationManager.now = previousClock }

        let manager = NotificationManager.shared
        let config = IntervalConfiguration(type: .hours, value: 2)
        let lastPending = now.addingTimeInterval(3600)

        let triggers = manager.createBatchedTriggers(
            for: config, batchSize: 1, continuingFrom: [lastPending],
            earliestFire: now, deferredStart: nil
        )

        let trigger = try #require(triggers.first)
        let firedDate = try #require(fireDate(of: trigger))
        #expect(abs(firedDate.timeIntervalSince(lastPending) - 7200) < 1)
    }
}
