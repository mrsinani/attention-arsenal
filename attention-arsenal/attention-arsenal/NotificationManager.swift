import Foundation
import UserNotifications
import CoreData

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

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

        let batchedArsenals = activeArsenals.filter { $0.1.usesBatchedScheduling }
        guard !batchedArsenals.isEmpty else { return }

        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            var totalPending = requests.count

            for (arsenal, config) in batchedArsenals {
                let baseId = self.baseIdentifier(for: arsenal)
                let pendingForArsenal = requests.filter { $0.identifier.hasPrefix(baseId) }
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

    private func nextNotificationIndex(from pending: [UNNotificationRequest], baseId: String) -> Int {
        let prefix = baseId + "_"
        let indices = pending.compactMap { request -> Int? in
            guard request.identifier.hasPrefix(prefix) else { return nil }
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
        let triggers = createBatchedTriggers(
            for: config,
            batchSize: count,
            continuingFrom: pendingDates
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

        cancelNotifications(for: arsenal)

        let batchSize: Int
        if config.usesBatchedScheduling {
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
        let triggers = createTriggers(for: config, batchSize: batchSize)

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

    private func fetchActiveBatchedArsenalCount() -> Int {
        let context = PersistenceController.shared.container.viewContext
        var count = 1
        context.performAndWait {
            let request: NSFetchRequest<Arsenal> = Arsenal.fetchRequest()
            request.predicate = NSPredicate(format: "isCompleted == NO")
            do {
                count = max(1, try context.fetch(request).filter {
                    IntervalConfiguration(from: $0).usesBatchedScheduling
                }.count)
            } catch {
                count = 1
            }
        }
        return count
    }

    private func createTriggers(for config: IntervalConfiguration, batchSize: Int) -> [UNNotificationTrigger] {
        if config.usesBatchedScheduling {
            return createBatchedTriggers(for: config, batchSize: batchSize, continuingFrom: nil)
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
            guard let targetDate = config.targetDate, targetDate > Date() else { return [] }
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
    private func createBatchedTriggers(
        for config: IntervalConfiguration,
        batchSize: Int,
        continuingFrom pendingDates: [Date]?
    ) -> [UNNotificationTrigger] {
        let userCalendar = Calendar(identifier: .gregorian)
        let userTimeZone = TimeZone.current

        switch config.type {
        case .hours:
            guard let timeInterval = config.timeIntervalInSeconds else { return [] }
            var triggers: [UNNotificationTrigger] = []
            var fireDate: Date
            if let latest = pendingDates?.max() {
                fireDate = latest.addingTimeInterval(timeInterval)
            } else {
                fireDate = Date().addingTimeInterval(timeInterval)
            }
            for _ in 0..<batchSize {
                var dc = userCalendar.dateComponents(in: userTimeZone, from: fireDate)
                dc.second = 0
                dc.calendar = userCalendar
                dc.timeZone = userTimeZone
                triggers.append(UNCalendarNotificationTrigger(dateMatching: dc, repeats: false))
                fireDate = fireDate.addingTimeInterval(timeInterval)
            }
            return triggers

        case .weekly where config.value > 1:
            let selectedDays = config.days.selectedDays
            guard !selectedDays.isEmpty else { return [] }

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
                } else if let first = userCalendar.nextDate(
                    after: Date(),
                    matching: matchComponents,
                    matchingPolicy: .nextTime
                ) {
                    nextDate = first
                } else {
                    continue
                }

                for _ in 0..<countPerWeekday {
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

        case .monthly where config.value > 1:
            let selectedDays = config.monthDays.selectedDays
            guard !selectedDays.isEmpty else { return [] }

            let intervalMonths = Int(config.value)
            let countPerDay = max(1, batchSize / selectedDays.count)
            var triggers: [UNNotificationTrigger] = []

            for day in selectedDays {
                var matchComponents = DateComponents()
                matchComponents.day = day
                matchComponents.hour = Int(config.hour)
                matchComponents.minute = Int(config.minute)
                matchComponents.second = 0

                let dayDates = pendingDates?.filter {
                    userCalendar.component(.day, from: $0) == day
                } ?? []

                var nextDate: Date
                if let latest = dayDates.max() {
                    nextDate = userCalendar.date(byAdding: .month, value: intervalMonths, to: latest)
                        ?? latest
                } else if let first = userCalendar.nextDate(
                    after: Date(),
                    matching: matchComponents,
                    matchingPolicy: .nextTime
                ) {
                    nextDate = first
                } else {
                    continue
                }

                for _ in 0..<countPerDay {
                    var dc = userCalendar.dateComponents(in: userTimeZone, from: nextDate)
                    dc.second = 0
                    dc.calendar = userCalendar
                    dc.timeZone = userTimeZone
                    triggers.append(UNCalendarNotificationTrigger(dateMatching: dc, repeats: false))
                    nextDate = userCalendar.date(byAdding: .month, value: intervalMonths, to: nextDate)
                        ?? nextDate
                }
            }
            return triggers

        default:
            return []
        }
    }

    // MARK: - Notification Management
    func cancelNotifications(for arsenal: Arsenal) {
        let baseIdentifier = baseIdentifier(for: arsenal)

        let semaphore = DispatchSemaphore(value: 0)

        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let identifiersToCancel = requests
                .filter { $0.identifier.hasPrefix(baseIdentifier) }
                .map { $0.identifier }

            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiersToCancel)
            #if DEBUG
            print("Cancelled \(identifiersToCancel.count) notification(s) for arsenal: \(arsenal.title ?? "Unknown")")
            #endif
            semaphore.signal()
        }

        semaphore.wait()
    }

    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
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
        content.title = "Attention Arsenal"
        content.body = arsenal.title ?? "You have a pending task"
        content.sound = .default
        content.userInfo = ["arsenalID": arsenal.objectID.uriRepresentation().absoluteString]

        return content
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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
        NotificationManager.shared.topUpBatchedNotificationsIfNeeded()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

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
