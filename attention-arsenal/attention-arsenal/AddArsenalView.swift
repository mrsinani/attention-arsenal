import SwiftUI
import CoreData

struct AddArsenalView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var arsenalManager: ArsenalManager
    @StateObject private var notificationManager = NotificationManager.shared
    
    @State private var title = ""
    @State private var description = ""
    @State private var intervalConfig = IntervalConfiguration.defaultDaily
    @State private var showingPermissionAlert = false
    @State private var isSaving = false
    
    // Character limits
    private let titleCharacterLimit = 50
    private let descriptionCharacterLimit = 200
    
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
            .navigationTitle("New Arsenal")
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
                        saveArsenal()
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
    
    private func saveArsenal() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let descriptionToUse = trimmedDescription.isEmpty ? nil : trimmedDescription
        
        // Check if notification permission is needed
        if intervalConfig.type != .none && !notificationManager.isAuthorized {
            showingPermissionAlert = true
            return
        }
        
        isSaving = true
        
        // Create arsenal with interval configuration
        if let _ = arsenalManager.createArsenal(
            title: trimmedTitle,
            description: descriptionToUse,
            intervalConfig: intervalConfig
        ) {
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
            // Retry saving the arsenal
            saveArsenal()
        }
    }
}

#Preview {
    AddArsenalView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(ArsenalManager())
}
