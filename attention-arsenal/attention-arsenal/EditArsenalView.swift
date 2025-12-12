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
    @State private var intervalConfig: IntervalConfiguration
    @State private var showingPermissionAlert = false
    @State private var isSaving = false
    
    // Character limits
    private let titleCharacterLimit = 50
    private let descriptionCharacterLimit = 200
    
    init(arsenal: Arsenal) {
        self.arsenal = arsenal
        let titleValue = arsenal.title ?? ""
        let descriptionValue = arsenal.arsenalDescription ?? ""
        self._title = State(initialValue: String(titleValue.prefix(50)))
        self._description = State(initialValue: String(descriptionValue.prefix(200)))
        self._intervalConfig = State(initialValue: IntervalConfiguration(from: arsenal))
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Arsenal Details")) {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Title", text: $title)
                            .font(.body)
                            .onChange(of: title) { oldValue, newValue in
                                if newValue.count > titleCharacterLimit {
                                    title = String(newValue.prefix(titleCharacterLimit))
                                }
                            }
                        
                        Text("\(title.count)/\(titleCharacterLimit)")
                            .font(.caption2)
                            .foregroundColor(title.count >= titleCharacterLimit ? .red : .secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Description (optional)", text: $description, axis: .vertical)
                            .font(.body)
                            .lineLimit(3...6)
                            .onChange(of: description) { oldValue, newValue in
                                if newValue.count > descriptionCharacterLimit {
                                    description = String(newValue.prefix(descriptionCharacterLimit))
                                }
                            }
                        
                        Text("\(description.count)/\(descriptionCharacterLimit)")
                            .font(.caption2)
                            .foregroundColor(description.count >= descriptionCharacterLimit ? .red : .secondary)
                    }
                }
                
                IntervalSelectionView(
                    intervalConfig: $intervalConfig,
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
        let descriptionToUse = trimmedDescription.isEmpty ? nil : trimmedDescription
        
        // Check if notification permission is needed
        if intervalConfig.type != .none && !notificationManager.isAuthorized {
            showingPermissionAlert = true
            return
        }
        
        isSaving = true
        
        // Update the arsenal
        let success = arsenalManager.updateArsenal(
            arsenal,
            title: trimmedTitle,
            description: descriptionToUse,
            intervalConfig: intervalConfig
        )
        
        if success {
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
    arsenal.createdDate = Date()
    arsenal.intervalType = 3 // daily
    arsenal.intervalValue = 1
    arsenal.notificationHour = 9
    arsenal.notificationMinute = 0
    arsenal.notificationDays = DaysBitmask.allDays.value
    
    return EditArsenalView(arsenal: arsenal)
        .environment(\.managedObjectContext, context)
        .environmentObject(ArsenalManager())
}
