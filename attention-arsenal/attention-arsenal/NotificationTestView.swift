import SwiftUI
import UserNotifications

struct NotificationTestView: View {
    @StateObject private var notificationManager = NotificationManager.shared
    @State private var pendingNotifications: [UNNotificationRequest] = []
    @State private var isLoading = false
    
    var body: some View {
        Form {
            Section(header: Text("Test Mode")) {
                Toggle("Enable Test Mode", isOn: Binding(
                    get: { notificationManager.testModeEnabled },
                    set: { notificationManager.setTestMode(enabled: $0) }
                ))
                
                if notificationManager.testModeEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Test notifications will fire in:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Stepper(
                            value: Binding(
                                get: { notificationManager.testOffsetMinutes },
                                set: { notificationManager.setTestOffset(minutes: $0) }
                            ),
                            in: 1...60,
                            step: 1
                        ) {
                            HStack {
                                Text("\(notificationManager.testOffsetMinutes) minute\(notificationManager.testOffsetMinutes == 1 ? "" : "s")")
                                Spacer()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    
                    Text("When enabled, daily/weekly/monthly notifications will fire in the specified time instead of their actual schedule. This allows you to test longer intervals without waiting.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                    
                    Text("⚠️ Note: After enabling/disabling test mode, you'll need to edit and save your arsenals to reschedule their notifications with the new mode.")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.top, 4)
                }
            }
            
            Section(header: Text("Pending Notifications")) {
                if isLoading {
                    ProgressView()
                } else if pendingNotifications.isEmpty {
                    Text("No pending notifications")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(pendingNotifications, id: \.identifier) { notification in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(notification.content.title)
                                .font(.headline)
                            Text(notification.content.body)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if let trigger = notification.trigger as? UNTimeIntervalNotificationTrigger {
                                let timeUntil = Int(trigger.timeInterval)
                                let minutes = timeUntil / 60
                                let seconds = timeUntil % 60
                                Text("Fires in: \(minutes)m \(seconds)s")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                            } else if notification.trigger is UNCalendarNotificationTrigger {
                                Text("Scheduled for calendar date")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                Button("Refresh") {
                    loadPendingNotifications()
                }
            }
            
            Section {
                Button("Clear All Notifications", role: .destructive) {
                    clearAllNotifications()
                }
            }
        }
        .navigationTitle("Test Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadPendingNotifications()
        }
    }
    
    private func loadPendingNotifications() {
        isLoading = true
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            DispatchQueue.main.async {
                self.pendingNotifications = requests
                self.isLoading = false
            }
        }
    }
    
    private func clearAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        loadPendingNotifications()
    }
}

#Preview {
    NavigationView {
        NotificationTestView()
    }
}

