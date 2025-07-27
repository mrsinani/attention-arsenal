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
    @State private var dueDate: Date
    @State private var hasDueDate: Bool
    @State private var selectedNotificationInterval: NotificationInterval
    @State private var showingPermissionAlert = false
    @State private var isSaving = false
    
    init(arsenal: Arsenal) {
        self.arsenal = arsenal
        self._title = State(initialValue: arsenal.title ?? "")
        self._description = State(initialValue: arsenal.arsenalDescription ?? "")
        self._dueDate = State(initialValue: arsenal.dueDate ?? Date())
        self._hasDueDate = State(initialValue: arsenal.dueDate != nil)
        self._selectedNotificationInterval = State(initialValue: NotificationInterval(rawValue: arsenal.notificationInterval) ?? .none)
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
                
                Section(header: Text("Due Date")) {
                    Toggle("Set due date", isOn: $hasDueDate)
                    
                    if hasDueDate {
                        DatePicker("Due Date", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.compact)
                    }
                }
                
                Section(header: Text("Notifications")) {
                    Picker("Reminder Interval", selection: $selectedNotificationInterval) {
                        ForEach(NotificationInterval.allCases, id: \.self) { interval in
                            Text(interval.displayName)
                                .tag(interval)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    if selectedNotificationInterval != .none && !notificationManager.isAuthorized {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text("Notification permission required")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
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
        
        let dueDateToUse = hasDueDate ? dueDate : nil
        let descriptionToUse = trimmedDescription.isEmpty ? nil : trimmedDescription
        
        // Check if notification permission is needed
        if selectedNotificationInterval != .none && !notificationManager.isAuthorized {
            showingPermissionAlert = true
            return
        }
        
        isSaving = true
        
        // Cancel existing notifications before updating
        notificationManager.cancelNotifications(for: arsenal)
        
        // Update the arsenal
        let success = arsenalManager.updateArsenal(
            arsenal,
            title: trimmedTitle,
            description: descriptionToUse,
            dueDate: dueDateToUse,
            notificationInterval: selectedNotificationInterval.rawValue
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
    arsenal.dueDate = Date()
    arsenal.notificationInterval = 60
    
    return EditArsenalView(arsenal: arsenal)
        .environment(\.managedObjectContext, context)
        .environmentObject(ArsenalManager())
} 