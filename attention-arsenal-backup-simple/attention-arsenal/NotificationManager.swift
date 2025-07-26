import Foundation
import UserNotifications
import CoreData

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    @Published var isAuthorized = false
    
    private init() {
        checkAuthorizationStatus()
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
    
    // MARK: - Notification Scheduling
    func scheduleNotification(for arsenal: Arsenal) {
        guard arsenal.notificationInterval > 0 else { return }
        
        // Cancel any existing notifications for this arsenal
        cancelNotifications(for: arsenal)
        
        let content = UNMutableNotificationContent()
        content.title = "Attention Arsenal"
        content.body = arsenal.title ?? "You have a pending task"
        content.sound = .default
        
        // Add arsenal ID to user info for identification
        content.userInfo = ["arsenalID": arsenal.objectID.uriRepresentation().absoluteString]
        
        // Create trigger that repeats based on the interval
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(arsenal.notificationInterval * 60), // Convert minutes to seconds
            repeats: true
        )
        
        // Create unique identifier for this arsenal's notifications
        let identifier = "arsenal_\(arsenal.objectID.uriRepresentation().absoluteString)"
        
        let request = UNNotificationRequest(
            identifier: identifier,
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
    
    // MARK: - Notification Management
    func cancelNotifications(for arsenal: Arsenal) {
        let identifier = "arsenal_\(arsenal.objectID.uriRepresentation().absoluteString)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        print("Cancelled notifications for arsenal: \(arsenal.title ?? "Unknown")")
    }
    
    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        print("Cancelled all pending notifications")
    }
    
    func updateNotification(for arsenal: Arsenal) {
        // Cancel existing notifications and schedule new ones if needed
        cancelNotifications(for: arsenal)
        
        // Only schedule if arsenal is not completed and has notification interval
        if !arsenal.isCompleted && arsenal.notificationInterval > 0 {
            scheduleNotification(for: arsenal)
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
    func getPendingNotificationCount() async -> Int {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return requests.count
    }
    
    func listPendingNotifications() async -> [UNNotificationRequest] {
        return await UNUserNotificationCenter.current().pendingNotificationRequests()
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