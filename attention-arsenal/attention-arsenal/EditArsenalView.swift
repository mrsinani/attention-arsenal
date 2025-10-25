import SwiftUI
import CoreData

struct EditArsenalView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var arsenalManager: ArsenalManager
    @StateObject private var notificationManager = NotificationManager.shared
    
    let arsenal: Arsenal
    
    @State private var title: String
    @State private var description: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var hasDateRange: Bool
    @State private var selectedNotificationInterval: NotificationInterval
    @State private var showingPermissionAlert = false
    @State private var isSaving = false
    
    // Custom duration state
    @State private var customMinutes: Int32 = 0
    @State private var customValue: Int32 = 1
    @State private var customUnit: DurationUnit = .days
    
    init(arsenal: Arsenal) {
        self.arsenal = arsenal
        self._title = State(initialValue: arsenal.title ?? "")
        self._description = State(initialValue: arsenal.arsenalDescription ?? "")
        self._startDate = State(initialValue: arsenal.startDate ?? Date())
        self._endDate = State(initialValue: arsenal.endDate ?? Date().addingTimeInterval(3600))
        self._hasDateRange = State(initialValue: arsenal.startDate != nil || arsenal.endDate != nil)
        
        // Determine interval type
        let intervalMinutes = Int32(arsenal.notificationInterval)
        if let standardInterval = NotificationInterval(rawValue: intervalMinutes) {
            self._selectedNotificationInterval = State(initialValue: standardInterval)
        } else if intervalMinutes > 0 {
            // Custom interval
            self._selectedNotificationInterval = State(initialValue: .custom)
            self._customMinutes = State(initialValue: intervalMinutes)
            
            // Parse into custom duration
            if let custom = CustomDuration.fromMinutes(intervalMinutes) {
                self._customValue = State(initialValue: custom.value)
                self._customUnit = State(initialValue: custom.unit)
            }
        } else {
            self._selectedNotificationInterval = State(initialValue: .none)
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Arsenal Details")) {
                    TextField("Title", text: $title)
                        .font(.body)
                    
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .font(.body)
                        .lineLimit(3...6)
                }
                
                Section(header: Text("Date Range")) {
                    Toggle("Set date range", isOn: $hasDateRange)
                    
                    if hasDateRange {
                        DatePicker("Start", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.compact)
                        
                        DatePicker("End", selection: $endDate, in: startDate..., displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.compact)
                    }
                }
                
                NotificationIntervalSection(
                    selectedInterval: $selectedNotificationInterval,
                    customMinutes: $customMinutes,
                    customValue: $customValue,
                    customUnit: $customUnit,
                    isAuthorized: notificationManager.isAuthorized
                )
            }
            .navigationTitle("Edit Arsenal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        updateArsenal()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                    .overlay(
                        Group {
                            if isSaving {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    )
                }
            }
            .alert("Notification Permission Required", isPresented: $showingPermissionAlert) {
                Button("Request Permission") {
                    Task {
                        await requestNotificationPermission()
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("To receive reminders for this arsenal, please allow notifications.")
            }
        }
    }
    
    private func updateArsenal() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let startDateToUse = hasDateRange ? startDate : nil
        let endDateToUse = hasDateRange ? endDate : nil
        let descriptionToUse = trimmedDescription.isEmpty ? nil : trimmedDescription
        
        // Check if notification permission is needed
        let needsPermission = (selectedNotificationInterval == .custom && customMinutes > 0) || 
                             (selectedNotificationInterval != .none && selectedNotificationInterval != .custom)
        if needsPermission && !notificationManager.isAuthorized {
            showingPermissionAlert = true
            return
        }
        
        isSaving = true
        
        // Determine the actual notification interval to use
        let intervalToUse: Int32
        if selectedNotificationInterval == .custom {
            // If custom is 0, treat as no notifications
            intervalToUse = customMinutes == 0 ? 0 : customMinutes
        } else {
            intervalToUse = selectedNotificationInterval.rawValue
        }
        
        // Cancel existing notifications before updating
        notificationManager.cancelNotifications(for: arsenal)
        
        // Update the arsenal
        let success = arsenalManager.updateArsenal(
            arsenal,
            title: trimmedTitle,
            description: descriptionToUse,
            startDate: startDateToUse,
            endDate: endDateToUse,
            notificationInterval: intervalToUse
        )
        
        if success {
            // Schedule new notification if needed
            if selectedNotificationInterval != .none {
                notificationManager.scheduleNotification(for: arsenal)
            }
            
            isSaving = false
            dismiss()
        } else {
            isSaving = false
            // You could add error handling here
        }
    }
    
    private func requestNotificationPermission() async {
        let granted = await notificationManager.requestNotificationPermission()
        if granted {
            // Retry updating the arsenal
            updateArsenal()
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let arsenal = Arsenal(context: context)
    arsenal.title = "Sample Arsenal"
    arsenal.arsenalDescription = "Sample description"
    arsenal.startDate = Date()
    arsenal.endDate = Date().addingTimeInterval(3600)
    arsenal.notificationInterval = 60
    
    return EditArsenalView(arsenal: arsenal)
        .environment(\.managedObjectContext, context)
        .environmentObject(ArsenalManager())
} 