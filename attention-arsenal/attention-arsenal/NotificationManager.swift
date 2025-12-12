import Foundation
import UserNotifications
import CoreData

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    @Published var isAuthorized = false
    @Published var testModeEnabled = false
    @Published var testOffsetMinutes: Int = 1 // Minutes from now to schedule test notifications
    
    private init() {
        checkAuthorizationStatus()
        // Load test mode setting from UserDefaults
        testModeEnabled = UserDefaults.standard.bool(forKey: "notificationTestMode")
        testOffsetMinutes = UserDefaults.standard.integer(forKey: "notificationTestOffset")
        if testOffsetMinutes == 0 {
            testOffsetMinutes = 1 // Default to 1 minute
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
    
    func setTestMode(enabled: Bool) {
        testModeEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "notificationTestMode")
        // Note: Existing notifications won't be rescheduled automatically
        // User needs to edit and save arsenals to reschedule with new test mode
    }
    
    func setTestOffset(minutes: Int) {
        testOffsetMinutes = minutes
        UserDefaults.standard.set(minutes, forKey: "notificationTestOffset")
        // Note: Existing notifications won't be rescheduled automatically
        // User needs to edit and save arsenals to reschedule with new offset
    }
    
    // MARK: - Notification Scheduling
    func scheduleNotification(for arsenal: Arsenal) {
        let config = IntervalConfiguration(from: arsenal)
        
        guard config.type != .none else { return }
        
        // Cancel any existing notifications for this arsenal first
        cancelNotifications(for: arsenal)
        
        let content = createNotificationContent(for: arsenal)
        content.categoryIdentifier = "ARSENAL_REMINDER"
        
        let identifier = "arsenal_\(arsenal.objectID.uriRepresentation().absoluteString)"
        
        // Create triggers based on interval type
        let triggers = createTriggers(for: config, identifier: identifier)
        
        // Schedule all notification requests
        for (index, trigger) in triggers.enumerated() {
            let request = UNNotificationRequest(
                identifier: "\(identifier)_\(index)",
                content: content,
                trigger: trigger
            )
            
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("Error scheduling notification for arsenal: \(error)")
                } else {
                    print("Successfully scheduled notification for arsenal: \(arsenal.title ?? "Unknown")")
                }
            }
        }
    }
    
    private func createTriggers(for config: IntervalConfiguration, identifier: String) -> [UNNotificationTrigger] {
        // If test mode is enabled, use time interval triggers for quick testing
        if testModeEnabled {
            return createTestTriggers(for: config)
        }
        
        switch config.type {
        case .none:
            return []
            
        case .minutes, .hours:
            // Use time interval trigger for minutes/hours
            guard let timeInterval = config.timeIntervalInSeconds else { return [] }
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: timeInterval,
                repeats: true
            )
            return [trigger]
            
        case .daily:
            // Create a trigger for each selected day of week
            let selectedDays = config.days.selectedDays
            guard !selectedDays.isEmpty else { return [] }
            
            return selectedDays.map { weekday in
                var dateComponents = DateComponents()
                dateComponents.weekday = weekday.calendarWeekday // 1=Sunday, 7=Saturday
                dateComponents.hour = Int(config.hour)
                dateComponents.minute = Int(config.minute)
                
                // Log for debugging
                print("Scheduled daily notification for \(weekday.fullName) at \(config.hour):\(String(format: "%02d", config.minute))")
                
                return UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            }
            
        case .weekly:
            // Create a trigger for each selected day of week
            let selectedDays = config.days.selectedDays
            guard !selectedDays.isEmpty else { return [] }
            
            // Weekly is simplified to "every week" - fires every week on selected days
            return selectedDays.map { weekday in
                var dateComponents = DateComponents()
                dateComponents.weekday = weekday.calendarWeekday // 1=Sunday, 7=Saturday
                dateComponents.hour = Int(config.hour)
                dateComponents.minute = Int(config.minute)
                
                // Log for debugging
                print("Scheduled weekly notification for \(weekday.fullName) at \(config.hour):\(String(format: "%02d", config.minute))")
                
                return UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            }
            
        case .monthly:
            // Create a trigger for each selected day of month
            let selectedDays = config.monthDays.selectedDays
            guard !selectedDays.isEmpty else { return [] }
            
            return selectedDays.map { day in
                var dateComponents = DateComponents()
                dateComponents.day = day
                dateComponents.hour = Int(config.hour)
                dateComponents.minute = Int(config.minute)
                
                // Note: UNCalendarNotificationTrigger handles edge cases:
                // - If day 31 is selected but month has 30 days, it fires on the 30th
                // - If day 29-31 is selected in February, it fires on Feb 28/29 (leap year)
                // - This is the expected iOS behavior
                let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
                
                // Log for debugging
                print("Scheduled monthly notification for day \(day) at \(config.hour):\(String(format: "%02d", config.minute))")
                
                return trigger
            }
        }
    }
    
    /// Create test triggers that fire quickly for testing purposes
    private func createTestTriggers(for config: IntervalConfiguration) -> [UNNotificationTrigger] {
        switch config.type {
        case .none:
            return []
            
        case .minutes, .hours:
            // Use actual intervals for minutes/hours even in test mode
            guard let timeInterval = config.timeIntervalInSeconds else { return [] }
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: timeInterval,
                repeats: true
            )
            return [trigger]
            
        case .daily, .weekly, .monthly:
            // For daily/weekly/monthly, schedule to fire in testOffsetMinutes
            // Create one trigger per selected day/weekday/monthday
            let count: Int
            switch config.type {
            case .daily, .weekly:
                count = config.days.selectedDays.count
            case .monthly:
                count = config.monthDays.selectedDays.count
            default:
                count = 1
            }
            
            // Create triggers with small delays between them (1 second apart) so they don't all fire at once
            return (0..<count).map { index in
                let timeInterval = TimeInterval(testOffsetMinutes * 60) + TimeInterval(index)
                return UNTimeIntervalNotificationTrigger(
                    timeInterval: timeInterval,
                    repeats: false // Don't repeat in test mode
                )
            }
        }
    }
    
    // MARK: - Notification Management
    func cancelNotifications(for arsenal: Arsenal) {
        let baseIdentifier = "arsenal_\(arsenal.objectID.uriRepresentation().absoluteString)"
        
        // Get all pending notifications and filter by our identifier prefix
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let identifiersToCancel = requests
                .filter { $0.identifier.hasPrefix(baseIdentifier) }
                .map { $0.identifier }
            
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiersToCancel)
            print("Cancelled \(identifiersToCancel.count) notification(s) for arsenal: \(arsenal.title ?? "Unknown")")
        }
    }
    
    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        print("Cancelled all pending notifications")
    }
    
    func updateNotification(for arsenal: Arsenal) {
        // Cancel existing notifications and schedule new ones if needed
        cancelNotifications(for: arsenal)
        
        // Only schedule if arsenal is not completed and has notification configuration
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
        
        if let description = arsenal.arsenalDescription, !description.isEmpty {
            content.body = "\(arsenal.title ?? "Task"): \(description)"
        } else {
            content.body = arsenal.title ?? "You have a pending task"
        }
        
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
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound])
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Handle notification tap
        let userInfo = response.notification.request.content.userInfo
        
        if let arsenalIDString = userInfo["arsenalID"] as? String,
           let arsenalURL = URL(string: arsenalIDString),
           let arsenalID = PersistenceController.shared.container.persistentStoreCoordinator.managedObjectID(forURIRepresentation: arsenalURL) {
            
            // You can add navigation logic here to open the specific arsenal
            print("Notification tapped for arsenal ID: \(arsenalID)")
        }
        
        completionHandler()
    }
} 