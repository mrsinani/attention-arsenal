import Foundation
import UserNotifications
import CoreData

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    /// Injectable clock. Tests override this to simulate an arbitrary "now" against the
    /// real scheduling code — no separate test-only trigger logic to drift out of sync.
    static var now: () -> Date = { Date() }

    /// iOS limit for pending local notifications app-wide.
    private static let systemPendingLimit = 64
    private static let minBatchSize = 3
    private static let maxBatchSize = 20

    @Published var isAuthorized = false

    private init() {
        checkAuthorizationStatus()
        // Reschedule calendar-based notifications when the system timezone changes so
        // existing pending triggers remain aligned with the user's local time.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTimezoneChange),
            name: NSNotification.Name.NSSystemTimeZoneDidChange,
            object: nil
        )
    }

    @objc private func handleTimezoneChange() {
        DispatchQueue.main.async {
            self.rescheduleAllActiveNotifications()
        }
    }

    private func rescheduleAllActiveNotifications() {
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<Arsenal> = Arsenal.fetchRequest()
        request.predicate = NSPredicate(format: "isCompleted == NO")
        context.performAndWait {
            do {
                let arsenals = try context.fetch(request)
                for arsenal in arsenals {
                    let config = IntervalConfiguration(from: arsenal)
                    if config.type != .none {
                        self.scheduleNotification(for: arsenal)
                    }
                }
            } catch {
                print("Error rescheduling notifications after timezone change: \(error)")
            }
        }
    }

    // MARK: - Permission Management
    func requestNotificationPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )

            await MainActor.run {
                self.isAuthorized = granted
            }

            return granted
        } catch {
            print("Error requesting notification permission: \(error)")
            return false
        }
    }

    func checkAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    // MARK: - Batched Top-Up

    /// Refill pre-scheduled notification batches when the app becomes active.
    func topUpBatchedNotificationsIfNeeded() {
        let context = PersistenceController.shared.container.viewContext
        var activeArsenals: [(Arsenal, IntervalConfiguration)] = []

        context.performAndWait {
            let request: NSFetchRequest<Arsenal> = Arsenal.fetchRequest()
            request.predicate = NSPredicate(format: "isCompleted == NO")
            do {
                activeArsenals = try context.fetch(request).compactMap { arsenal in
                    let config = IntervalConfiguration(from: arsenal)
                    guard config.type != .none else { return nil }
                    return (arsenal, config)
                }
            } catch {
                print("Error fetching arsenals for notification top-up: \(error)")
            }
        }

        guard !activeArsenals.isEmpty else { return }

        // Both callbacks below hop to the main queue before doing anything. Two reasons:
        // the arsenals belong to the main-queue viewContext, and scheduleNotification blocks on
        // a semaphore — running that on UN's own callback queue would stop it from ever
        // delivering the nested getPendingNotificationRequests callback, deadlocking the app.
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
          DispatchQueue.main.async {
            var totalPending = requests.count

            // Activate arsenals whose deferred start time has passed but have no pending notifications.
            for (arsenal, _) in activeArsenals {
                if let start = arsenal.notificationStartDate, start > Self.now() { continue }

                let baseId = self.baseIdentifier(for: arsenal)
                let pendingCount = requests.filter { self.belongsToArsenal($0.identifier, baseId: baseId) }.count
                guard pendingCount == 0 else { continue }

                self.scheduleNotification(for: arsenal)
                let budget = self.perArsenalBatchBudget(
                    batchedCount: activeArsenals.filter {
                        IntervalConfiguration(from: $0.0).usesBatchedScheduling(deferredStart: $0.0.notificationStartDate)
                    }.count,
                    totalPending: totalPending
                )
                totalPending = min(Self.systemPendingLimit, totalPending + budget)
            }

            let batchedArsenals = activeArsenals.filter {
                $0.1.usesBatchedScheduling(deferredStart: $0.0.notificationStartDate)
            }
            guard !batchedArsenals.isEmpty else { return }

            UNUserNotificationCenter.current().getPendingNotificationRequests { refreshedRequests in
              DispatchQueue.main.async {
                totalPending = refreshedRequests.count

                for (arsenal, config) in batchedArsenals {
                    if let start = arsenal.notificationStartDate, start > Self.now() { continue }

                    let baseId = self.baseIdentifier(for: arsenal)
                    let pendingForArsenal = refreshedRequests.filter { self.belongsToArsenal($0.identifier, baseId: baseId) }
                    let pendingCount = pendingForArsenal.count

                    let budget = self.perArsenalBatchBudget(
                        batchedCount: batchedArsenals.count,
                        totalPending: totalPending
                    )
                    let lowWaterMark = self.lowWaterMark(for: budget)

                    if pendingCount == 0 {
                        self.scheduleNotification(for: arsenal, preferredBatchSize: budget)
                        totalPending = min(Self.systemPendingLimit, totalPending + budget)
                    } else if pendingCount < lowWaterMark {
                        let headroom = Self.systemPendingLimit - totalPending
                        let toAdd = min(budget - pendingCount, headroom)
                        guard toAdd > 0 else { continue }

                        let added = self.appendBatchedNotifications(
                            for: arsenal,
                            config: config,
                            count: toAdd,
                            existingPending: pendingForArsenal
                        )
                        totalPending += added
                    }
                }
              }
            }
          }
        }
    }

    private func perArsenalBatchBudget(batchedCount: Int, totalPending: Int) -> Int {
        let headroom = max(1, Self.systemPendingLimit - totalPending)
        return max(Self.minBatchSize, min(Self.maxBatchSize, headroom / max(1, batchedCount)))
    }

    private func lowWaterMark(for budget: Int) -> Int {
        max(2, budget / 4)
    }

    private func baseIdentifier(for arsenal: Arsenal) -> String {
        "arsenal_\(arsenal.objectID.uriRepresentation().absoluteString)"
    }

    /// Matches only this arsenal's own notification identifiers, anchored on the `_` index
    /// separator. Core Data object IDs are raw incrementing digits (p5, p50, p500, ...), so a
    /// bare `hasPrefix(baseId)` would also match p50/p500's notifications when acting on p5.
    /// Internal (not private) so tests can verify the fix directly against string literals.
    func belongsToArsenal(_ identifier: String, baseId: String) -> Bool {
        identifier.hasPrefix(baseId + "_")
    }

    private func nextNotificationIndex(from pending: [UNNotificationRequest], baseId: String) -> Int {
        let prefix = baseId + "_"
        let indices = pending.compactMap { request -> Int? in
            guard belongsToArsenal(request.identifier, baseId: baseId) else { return nil }
            return Int(request.identifier.dropFirst(prefix.count))
        }
        return (indices.max() ?? -1) + 1
    }

    private func pendingTriggerDates(from pending: [UNNotificationRequest]) -> [Date] {
        pending.compactMap { request in
            (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
        }
    }

    @discardableResult
    private func appendBatchedNotifications(
        for arsenal: Arsenal,
        config: IntervalConfiguration,
        count: Int,
        existingPending: [UNNotificationRequest]
    ) -> Int {
        guard count > 0 else { return 0 }

        let baseId = baseIdentifier(for: arsenal)
        let startIndex = nextNotificationIndex(from: existingPending, baseId: baseId)
        let pendingDates = pendingTriggerDates(from: existingPending)
        let deferredStart = arsenal.notificationStartDate
        let triggers = createBatchedTriggers(
            for: config,
            batchSize: count,
            continuingFrom: pendingDates,
            earliestFire: earliestFireDate(for: arsenal),
            deferredStart: deferredStart
        )
        guard !triggers.isEmpty else { return 0 }

        let content = createNotificationContent(for: arsenal)
        content.categoryIdentifier = "ARSENAL_REMINDER"

        for (offset, trigger) in triggers.enumerated() {
            let request = UNNotificationRequest(
                identifier: "\(baseId)_\(startIndex + offset)",
                content: content,
                trigger: trigger
            )
            UNUserNotificationCenter.current().add(request) { error in
                #if DEBUG
                if let error = error {
                    print("Error appending notification for arsenal: \(error)")
                }
                #endif
            }
        }

        #if DEBUG
        print("📅 Topped up \(triggers.count) notification(s) for: \(arsenal.title ?? "Unknown")")
        #endif

        return triggers.count
    }

    // MARK: - Notification Scheduling
    func scheduleNotification(for arsenal: Arsenal, preferredBatchSize: Int? = nil) {
        let config = IntervalConfiguration(from: arsenal)

        #if DEBUG
        print("📅 Scheduling notification for: \(arsenal.title ?? "Unknown")")
        print("   Type: \(config.type.displayName), Value: \(config.value)")
        if let interval = config.timeIntervalInSeconds {
            print("   Time interval: \(interval) seconds (\(interval/60) minutes)")
        }
        #endif

        guard config.type != .none else { return }

        let deferredStart = arsenal.notificationStartDate

        cancelNotifications(for: arsenal)

        let earliestFire = earliestFireDate(for: arsenal)
        let usesBatch = config.usesBatchedScheduling(deferredStart: deferredStart)

        let batchSize: Int
        if usesBatch {
            if let preferredBatchSize {
                batchSize = preferredBatchSize
            } else {
                let batchedCount = fetchActiveBatchedArsenalCount()
                let totalPending = getPendingNotificationCount()
                batchSize = perArsenalBatchBudget(batchedCount: batchedCount, totalPending: totalPending)
            }
        } else {
            batchSize = Self.maxBatchSize
        }

        let content = createNotificationContent(for: arsenal)
        content.categoryIdentifier = "ARSENAL_REMINDER"

        let identifier = baseIdentifier(for: arsenal)
        let triggers = createTriggers(
            for: config,
            batchSize: batchSize,
            earliestFire: earliestFire,
            deferredStart: deferredStart
        )

        #if DEBUG
        print("   Created \(triggers.count) trigger(s)")
        #endif

        for (index, trigger) in triggers.enumerated() {
            let request = UNNotificationRequest(
                identifier: "\(identifier)_\(index)",
                content: content,
                trigger: trigger
            )

            UNUserNotificationCenter.current().add(request) { error in
                #if DEBUG
                if let error = error {
                    print("Error scheduling notification for arsenal: \(error)")
                } else {
                    print("Successfully scheduled notification for arsenal: \(arsenal.title ?? "Unknown")")
                }
                #endif
            }
        }
    }

    /// Internal (not private) so tests can drive it directly with an injected `Self.now`.
    func earliestFireDate(for arsenal: Arsenal) -> Date {
        if let start = arsenal.notificationStartDate {
            if start > Self.now() { return start }
            return max(Self.now(), start)
        }
        return Self.now()
    }

    private func fetchActiveBatchedArsenalCount() -> Int {
        let context = PersistenceController.shared.container.viewContext
        var count = 1
        context.performAndWait {
            let request: NSFetchRequest<Arsenal> = Arsenal.fetchRequest()
            request.predicate = NSPredicate(format: "isCompleted == NO")
            do {
                count = max(1, try context.fetch(request).filter {
                    IntervalConfiguration(from: $0).usesBatchedScheduling(deferredStart: $0.notificationStartDate)
                }.count)
            } catch {
                count = 1
            }
        }
        return count
    }

    /// Internal (not private) so tests can generate real triggers against an injected `Self.now`
    /// instead of waiting on the actual clock.
    func createTriggers(
        for config: IntervalConfiguration,
        batchSize: Int,
        earliestFire: Date,
        deferredStart: Date?
    ) -> [UNNotificationTrigger] {
        if config.usesBatchedScheduling(deferredStart: deferredStart) {
            return createBatchedTriggers(
                for: config,
                batchSize: batchSize,
                continuingFrom: nil,
                earliestFire: earliestFire,
                deferredStart: deferredStart
            )
        }

        let userCalendar = Calendar(identifier: .gregorian)
        let userTimeZone = TimeZone.current

        switch config.type {
        case .none:
            return []

        case .minutes:
            guard let timeInterval = config.timeIntervalInSeconds else { return [] }
            return [UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: true)]

        case .oneTime:
            guard let targetDate = config.targetDate, targetDate > Self.now() else { return [] }
            var components = userCalendar.dateComponents(in: userTimeZone, from: targetDate)
            components.second = 0
            components.calendar = userCalendar
            components.timeZone = userTimeZone
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            #if DEBUG
            if let nextDate = trigger.nextTriggerDate() {
                let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
                print("📅 One-time notification scheduled for: \(fmt.string(from: nextDate))")
            }
            #endif
            return [trigger]

        case .daily:
            var dateComponents = DateComponents()
            dateComponents.calendar = userCalendar
            dateComponents.timeZone = userTimeZone
            dateComponents.hour = Int(config.hour)
            dateComponents.minute = Int(config.minute)
            dateComponents.second = 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

            #if DEBUG
            if let nextDate = trigger.nextTriggerDate() {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                print("📅 Daily notification scheduled for \(config.hour):\(String(format: "%02d", config.minute))")
                print("   Next trigger: \(formatter.string(from: nextDate))")
            }
            #endif

            return [trigger]

        case .weekly:
            let selectedDays = config.days.selectedDays
            guard !selectedDays.isEmpty else { return [] }

            return selectedDays.map { weekday in
                var dc = DateComponents()
                dc.calendar = userCalendar
                dc.timeZone = userTimeZone
                dc.weekday = weekday.calendarWeekday
                dc.hour = Int(config.hour)
                dc.minute = Int(config.minute)
                dc.second = 0
                let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
                #if DEBUG
                if let nextDate = trigger.nextTriggerDate() {
                    let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
                    print("📅 Weekly [\(weekday.fullName)] at \(config.hour):\(String(format: "%02d", config.minute)) → \(fmt.string(from: nextDate))")
                }
                #endif
                return trigger
            }

        case .monthly:
            let selectedDays = config.monthDays.selectedDays
            guard !selectedDays.isEmpty else { return [] }

            return selectedDays.map { day in
                var dc = DateComponents()
                dc.calendar = userCalendar
                dc.timeZone = userTimeZone
                dc.day = day
                dc.hour = Int(config.hour)
                dc.minute = Int(config.minute)
                dc.second = 0
                let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
                #if DEBUG
                print("📅 Monthly [day \(day)] at \(config.hour):\(String(format: "%02d", config.minute))")
                #endif
                return trigger
            }

        case .hours:
            return []
        }
    }

    /// Pre-scheduled calendar triggers for batched interval types.
    /// Pass `continuingFrom` when topping up so new fires continue from the latest pending date.
    /// Internal (not private) so tests can generate real triggers against an injected `Self.now`
    /// instead of waiting on the actual clock.
    func createBatchedTriggers(
        for config: IntervalConfiguration,
        batchSize: Int,
        continuingFrom pendingDates: [Date]?,
        earliestFire: Date,
        deferredStart: Date?
    ) -> [UNNotificationTrigger] {
        let userCalendar = Calendar(identifier: .gregorian)
        let userTimeZone = TimeZone.current

        switch config.type {
        // .minutes only lands here when a deferred start is still pending; the walk-forward
        // logic is identical to .hours, just a smaller stride.
        case .hours, .minutes:
            guard let timeInterval = config.timeIntervalInSeconds else { return [] }
            var triggers: [UNNotificationTrigger] = []
            var fireDate: Date
            if let latest = pendingDates?.max() {
                fireDate = latest.addingTimeInterval(timeInterval)
            } else if deferredStart != nil {
                fireDate = earliestFire
            } else {
                fireDate = Self.now().addingTimeInterval(timeInterval)
            }
            for _ in 0..<batchSize {
                guard fireDate > Self.now() else {
                    fireDate = fireDate.addingTimeInterval(timeInterval)
                    continue
                }
                var dc = userCalendar.dateComponents(in: userTimeZone, from: fireDate)
                dc.second = 0
                dc.calendar = userCalendar
                dc.timeZone = userTimeZone
                triggers.append(UNCalendarNotificationTrigger(dateMatching: dc, repeats: false))
                fireDate = fireDate.addingTimeInterval(timeInterval)
            }
            return triggers

        case .daily:
            return createCalendarBatchedTriggers(
                for: config,
                batchSize: batchSize,
                pendingDates: pendingDates,
                earliestFire: earliestFire,
                calendar: userCalendar,
                timeZone: userTimeZone
            )

        case .weekly:
            let selectedDays = config.days.selectedDays
            guard !selectedDays.isEmpty else { return [] }

            if config.value == 1 {
                return createCalendarBatchedTriggers(
                    for: config,
                    batchSize: batchSize,
                    pendingDates: pendingDates,
                    earliestFire: earliestFire,
                    calendar: userCalendar,
                    timeZone: userTimeZone
                )
            }

            let intervalWeeks = Int(config.value)
            let countPerWeekday = max(1, batchSize / selectedDays.count)
            var triggers: [UNNotificationTrigger] = []

            for weekday in selectedDays {
                var matchComponents = DateComponents()
                matchComponents.weekday = weekday.calendarWeekday
                matchComponents.hour = Int(config.hour)
                matchComponents.minute = Int(config.minute)
                matchComponents.second = 0

                let weekdayDates = pendingDates?.filter {
                    userCalendar.component(.weekday, from: $0) == weekday.calendarWeekday
                } ?? []

                var nextDate: Date
                if let latest = weekdayDates.max() {
                    nextDate = userCalendar.date(byAdding: .weekOfYear, value: intervalWeeks, to: latest)
                        ?? latest.addingTimeInterval(TimeInterval(intervalWeeks * 7 * 86400))
                } else if let first = nextCalendarFire(
                    after: earliestFire.addingTimeInterval(-1),
                    config: config,
                    calendar: userCalendar,
                    requiredWeekday: weekday.calendarWeekday
                ) {
                    nextDate = first
                } else {
                    continue
                }

                for _ in 0..<countPerWeekday {
                    guard nextDate > Self.now() else {
                        nextDate = userCalendar.date(byAdding: .weekOfYear, value: intervalWeeks, to: nextDate)
                            ?? nextDate.addingTimeInterval(TimeInterval(intervalWeeks * 7 * 86400))
                        continue
                    }
                    var dc = userCalendar.dateComponents(in: userTimeZone, from: nextDate)
                    dc.second = 0
                    dc.calendar = userCalendar
                    dc.timeZone = userTimeZone
                    triggers.append(UNCalendarNotificationTrigger(dateMatching: dc, repeats: false))
                    nextDate = userCalendar.date(byAdding: .weekOfYear, value: intervalWeeks, to: nextDate)
                        ?? nextDate.addingTimeInterval(TimeInterval(intervalWeeks * 7 * 86400))
                }
            }
            return triggers

        case .monthly:
            let selectedDays = config.monthDays.selectedDays
            guard !selectedDays.isEmpty else { return [] }

            if config.value == 1 {
                return createMonthlyBatchedTriggers(
                    for: config,
                    batchSize: batchSize,
                    pendingDates: pendingDates,
                    earliestFire: earliestFire,
                    calendar: userCalendar,
                    timeZone: userTimeZone,
                    intervalMonths: 1
                )
            }

            let intervalMonths = Int(config.value)
            let countPerDay = max(1, batchSize / selectedDays.count)
            var triggers: [UNNotificationTrigger] = []

            for day in selectedDays {
                let dayDates = pendingDates?.filter {
                    userCalendar.component(.day, from: $0) == day
                } ?? []

                var nextDate: Date
                if let latest = dayDates.max() {
                    nextDate = userCalendar.date(byAdding: .month, value: intervalMonths, to: latest) ?? latest
                } else if let first = nextMonthlyFire(
                    after: earliestFire.addingTimeInterval(-1),
                    config: config,
                    calendar: userCalendar,
                    day: day
                ) {
                    nextDate = first
                } else {
                    continue
                }

                for _ in 0..<countPerDay {
                    guard nextDate > Self.now() else {
                        nextDate = userCalendar.date(byAdding: .month, value: intervalMonths, to: nextDate) ?? nextDate
                        continue
                    }
                    var dc = userCalendar.dateComponents(in: userTimeZone, from: nextDate)
                    dc.second = 0
                    dc.calendar = userCalendar
                    dc.timeZone = userTimeZone
                    triggers.append(UNCalendarNotificationTrigger(dateMatching: dc, repeats: false))
                    nextDate = userCalendar.date(byAdding: .month, value: intervalMonths, to: nextDate) ?? nextDate
                }
            }
            return triggers

        default:
            return []
        }
    }

    private func createCalendarBatchedTriggers(
        for config: IntervalConfiguration,
        batchSize: Int,
        pendingDates: [Date]?,
        earliestFire: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> [UNNotificationTrigger] {
        var triggers: [UNNotificationTrigger] = []
        var searchAfter = pendingDates?.max() ?? earliestFire.addingTimeInterval(-1)
        var generated = 0

        while generated < batchSize {
            guard let next = nextCalendarFire(
                after: searchAfter,
                config: config,
                calendar: calendar,
                requiredWeekday: nil
            ), next > searchAfter else { break }

            guard next > Self.now() else {
                searchAfter = next
                continue
            }

            var dc = calendar.dateComponents(in: timeZone, from: next)
            dc.second = 0
            dc.calendar = calendar
            dc.timeZone = timeZone
            triggers.append(UNCalendarNotificationTrigger(dateMatching: dc, repeats: false))
            searchAfter = next
            generated += 1
        }

        return triggers
    }

    private func createMonthlyBatchedTriggers(
        for config: IntervalConfiguration,
        batchSize: Int,
        pendingDates: [Date]?,
        earliestFire: Date,
        calendar: Calendar,
        timeZone: TimeZone,
        intervalMonths: Int
    ) -> [UNNotificationTrigger] {
        let selectedDays = config.monthDays.selectedDays
        guard !selectedDays.isEmpty else { return [] }

        let countPerDay = max(1, batchSize / selectedDays.count)
        var triggers: [UNNotificationTrigger] = []

        for day in selectedDays {
            let dayDates = pendingDates?.filter {
                calendar.component(.day, from: $0) == day
            } ?? []

            var searchAfter = dayDates.max() ?? earliestFire.addingTimeInterval(-1)
            var generated = 0

            while generated < countPerDay {
                guard let next = nextMonthlyFire(
                    after: searchAfter,
                    config: config,
                    calendar: calendar,
                    day: day
                ), next > searchAfter else { break }

                guard next > Self.now() else {
                    searchAfter = next
                    continue
                }

                var dc = calendar.dateComponents(in: timeZone, from: next)
                dc.second = 0
                dc.calendar = calendar
                dc.timeZone = timeZone
                triggers.append(UNCalendarNotificationTrigger(dateMatching: dc, repeats: false))
                searchAfter = next
                generated += 1
            }
        }

        return triggers
    }

    /// Next fire on or after `after` matching the configured calendar schedule.
    private func nextCalendarFire(
        after: Date,
        config: IntervalConfiguration,
        calendar: Calendar,
        requiredWeekday: Int?
    ) -> Date? {
        let selectedWeekdays: Set<Int>
        switch config.type {
        case .daily, .weekly:
            if let requiredWeekday {
                selectedWeekdays = [requiredWeekday]
            } else {
                selectedWeekdays = Set(config.days.selectedDays.map { $0.calendarWeekday })
            }
        default:
            return nil
        }

        guard !selectedWeekdays.isEmpty else { return nil }

        var probe = after.addingTimeInterval(1)
        for _ in 0..<400 {
            let weekday = calendar.component(.weekday, from: probe)
            guard selectedWeekdays.contains(weekday) else {
                probe = calendar.startOfDay(for: probe).addingTimeInterval(86400)
                continue
            }

            var components = calendar.dateComponents([.year, .month, .day], from: probe)
            components.hour = Int(config.hour)
            components.minute = Int(config.minute)
            components.second = 0

            if let candidate = calendar.date(from: components), candidate > after {
                return candidate
            }

            probe = calendar.startOfDay(for: probe).addingTimeInterval(86400)
        }

        return nil
    }

    private func nextMonthlyFire(
        after: Date,
        config: IntervalConfiguration,
        calendar: Calendar,
        day: Int
    ) -> Date? {
        var matchComponents = DateComponents()
        matchComponents.day = day
        matchComponents.hour = Int(config.hour)
        matchComponents.minute = Int(config.minute)
        matchComponents.second = 0

        // .nextTime silently rolls an invalid date (e.g. day 31 in April) forward to the 1st of
        // the next month at midnight — losing both the day and the configured time. .strict
        // skips months that don't have the requested day entirely, landing on day 31 at the
        // configured hour in the next month that does (e.g. May 31 9am, not May 1 12am).
        return calendar.nextDate(after: after, matching: matchComponents, matchingPolicy: .strict)
    }

    // MARK: - Notification Management
    func cancelNotifications(for arsenal: Arsenal) {
        // Read everything off the managed object HERE, on the caller's thread. These closures
        // run on a UN background queue, and `arsenal` belongs to the main-queue viewContext —
        // touching it in there makes Core Data hop to the main queue, which is blocked below.
        let baseIdentifier = baseIdentifier(for: arsenal)
        let title = arsenal.title ?? "Unknown"
        let center = UNUserNotificationCenter.current()

        // Clearing already-delivered notifications keeps a reminder that fired moments before a
        // delete/complete from lingering in Notification Center. It doesn't affect scheduling
        // order, so it's fire-and-forget — nesting it inside the wait below caused a deadlock.
        center.getDeliveredNotifications { delivered in
            let deliveredToCancel = delivered
                .filter { self.belongsToArsenal($0.request.identifier, baseId: baseIdentifier) }
                .map { $0.request.identifier }
            center.removeDeliveredNotifications(withIdentifiers: deliveredToCancel)
        }

        // Pending removal must finish before the caller schedules replacements, otherwise the
        // remove can land on the newly-added requests (they reuse the same identifiers).
        let semaphore = DispatchSemaphore(value: 0)
        center.getPendingNotificationRequests { requests in
            let identifiersToCancel = requests
                .filter { self.belongsToArsenal($0.identifier, baseId: baseIdentifier) }
                .map { $0.identifier }
            center.removePendingNotificationRequests(withIdentifiers: identifiersToCancel)
            #if DEBUG
            print("Cancelled \(identifiersToCancel.count) pending notification(s) for arsenal: \(title)")
            #endif
            semaphore.signal()
        }

        // ponytail: timeout so a stalled callback degrades to a stale notification instead of a
        // frozen UI. Proper fix is making the whole schedule path async; this is the cheap guard.
        _ = semaphore.wait(timeout: .now() + 5)
    }

    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    func updateNotification(for arsenal: Arsenal) {
        cancelNotifications(for: arsenal)

        if !arsenal.isCompleted {
            let config = IntervalConfiguration(from: arsenal)
            if config.type != .none {
                scheduleNotification(for: arsenal)
            }
        }
    }

    // MARK: - Notification Content
    func createNotificationContent(for arsenal: Arsenal) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let config = IntervalConfiguration(from: arsenal)
        content.title = "Attention Arsenal"
        content.body = arsenal.title ?? "You have a pending task"
        content.sound = .default
        // Important arsenals break through Focus and Scheduled Summary (needs the
        // time-sensitive entitlement). Not .critical — that bypasses the ringer/silent switch
        // and requires Apple's approval. Everything else stays .active so routine nudges
        // can't train the user into revoking the permission.
        content.interruptionLevel = arsenal.isImportant ? .timeSensitive : .active
        content.relevanceScore = arsenal.isImportant ? 1.0 : 0.5
        content.userInfo = [
            "arsenalID": arsenal.objectID.uriRepresentation().absoluteString,
            "arsenalTitle": arsenal.title ?? "Untitled Arsenal",
            "intervalSummary": config.summary(notificationStartDate: arsenal.notificationStartDate)
        ]

        return content
    }

    /// Log when a scheduled notification is delivered (DEBUG builds only).
    static func logNotificationFired(_ notification: UNNotification, context: String = "delivered") {
        #if DEBUG
        let content = notification.request.content
        let userInfo = content.userInfo
        let title = userInfo["arsenalTitle"] as? String ?? content.body
        let interval = userInfo["intervalSummary"] as? String ?? "unknown interval"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let firedAt = formatter.string(from: Date())
        print("🔔 Arsenal \(context) at \(firedAt) | \"\(title)\" | \(interval)")
        #endif
    }

    // MARK: - Notification Statistics
    func getPendingNotificationCount() -> Int {
        var count = 0
        let semaphore = DispatchSemaphore(value: 0)

        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            count = requests.count
            semaphore.signal()
        }

        semaphore.wait()
        return count
    }

    func listPendingNotifications() -> [UNNotificationRequest] {
        var requests: [UNNotificationRequest] = []
        let semaphore = DispatchSemaphore(value: 0)

        UNUserNotificationCenter.current().getPendingNotificationRequests { pendingRequests in
            requests = pendingRequests
            semaphore.signal()
        }

        semaphore.wait()
        return requests
    }
}

// MARK: - Notification Delegate
class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    private static var recentlyDeliveredNotificationIDs = Set<String>()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Self.recentlyDeliveredNotificationIDs.insert(notification.request.identifier)
        NotificationManager.logNotificationFired(notification, context: "delivered")
        completionHandler([.banner, .sound])
        NotificationManager.shared.topUpBatchedNotificationsIfNeeded()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            Self.recentlyDeliveredNotificationIDs.remove(notification.request.identifier)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let requestID = response.notification.request.identifier
        if !Self.recentlyDeliveredNotificationIDs.contains(requestID) {
            NotificationManager.logNotificationFired(response.notification, context: "opened from notification")
        }

        if let arsenalIDString = userInfo["arsenalID"] as? String,
           let arsenalURL = URL(string: arsenalIDString),
           let arsenalID = PersistenceController.shared.container.persistentStoreCoordinator.managedObjectID(forURIRepresentation: arsenalURL) {

            #if DEBUG
            print("Notification tapped for arsenal ID: \(arsenalID)")
            #endif
        }

        NotificationManager.shared.topUpBatchedNotificationsIfNeeded()
        completionHandler()
    }
}
