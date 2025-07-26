import SwiftUI
import UserNotifications

@main
struct app_templateApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var notificationManager = NotificationManager.shared
    
    init() {
        // Set up notification delegate
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(notificationManager)
                .task {
                    // Request notification permission on app startup
                    await requestNotificationPermissionOnStartup()
                }
        }
    }
    
    private func requestNotificationPermissionOnStartup() async {
        // Check current authorization status
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        
        // Only request if not determined (first time) or denied (user might want to change)
        if settings.authorizationStatus == .notDetermined {
            _ = await notificationManager.requestNotificationPermission()
        }
    }
}
