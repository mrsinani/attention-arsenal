import SwiftUI
import UserNotifications
import AppIntents
import GoogleSignIn
import MSAL

@main
struct attention_arsenalApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var gmailAuthManager = GmailAuthManager.shared
    @StateObject private var outlookAuthManager = OutlookAuthManager.shared
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        // Set up notification delegate
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        
        // Register notification categories
        setupNotificationCategories()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(notificationManager)
                .environmentObject(gmailAuthManager)
                .environmentObject(outlookAuthManager)
                .onOpenURL { url in
                    // Handle OAuth callbacks
                    // Try Google Sign-In first
                    if GIDSignIn.sharedInstance.handle(url) {
                        return
                    }
                    // Try MSAL (Microsoft) if Google didn't handle it
                    MSALPublicClientApplication.handleMSALResponse(url, sourceApplication: nil)
                }
                .task {
                    // Request notification permission on app startup
                    await requestNotificationPermissionOnStartup()

                    // Restore previous sign-ins if available
                    await gmailAuthManager.restorePreviousSignIn()
                    await outlookAuthManager.restorePreviousSignIn()

                    // Refill pre-scheduled notification batches on launch
                    notificationManager.topUpBatchedNotificationsIfNeeded()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        notificationManager.topUpBatchedNotificationsIfNeeded()
                    case .background:
                        StatsManager.shared.forceBackupToiCloud()
                    default:
                        break
                    }
                }
        }
    }
    
    private func setupNotificationCategories() {
        // Create notification category for arsenal reminders
        let category = UNNotificationCategory(
            identifier: "ARSENAL_REMINDER",
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        // Register the category
        UNUserNotificationCenter.current().setNotificationCategories([category])
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
