import SwiftUI
import CoreData
import WidgetKit

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var arsenalManager = ArsenalManager()
    @EnvironmentObject var notificationManager: NotificationManager
    @State private var showingAddArsenal = false
    @State private var showingNotificationPermissionAlert = false
    @State private var showingSettings = false
    @State private var isEditMode = false
    
    var body: some View {
        NavigationView {
            ArsenalListView(isEditMode: $isEditMode)
                .navigationTitle("Attention Arsenal")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: {
                            showingSettings = true
                        }) {
                            Image(systemName: "gearshape")
                                .font(.title2)
                                .foregroundColor(.primary)
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if !isEditMode {
                            Button(action: {
                                showingAddArsenal = true
                            }) {
                                Image(systemName: "plus")
                                    .font(.title2)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                }
                .sheet(isPresented: $showingAddArsenal, onDismiss: {
                    // Trigger a small delay to ensure Core Data changes are processed
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        // This will trigger the @FetchRequest to refresh
                        viewContext.refreshAllObjects()
                    }
                }) {
                    AddArsenalView()
                        .environment(\.managedObjectContext, viewContext)
                }
                .sheet(isPresented: $showingSettings) {
                    SettingsView()
                }
        }
        .navigationViewStyle(.stack)
        .environmentObject(arsenalManager)
        .task {
            // Check notification permission status on view appear
            checkNotificationPermission()
        }
        .alert("Enable Notifications", isPresented: $showingNotificationPermissionAlert) {
            Button("Enable") {
                Task {
                    await requestNotificationPermission()
                }
            }
            Button("Not Now", role: .cancel) { }
        } message: {
            Text("Get reminded about your arsenals with customizable notification intervals.")
        }
    }
    
    private func checkNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                // Show permission request if denied (user might want to change their mind)
                if settings.authorizationStatus == .denied {
                    showingNotificationPermissionAlert = true
                }
            }
        }
    }
    
    private func requestNotificationPermission() async {
        _ = await notificationManager.requestNotificationPermission()
    }
}

struct ArsenalListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var arsenalManager: ArsenalManager
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Arsenal.createdDate, ascending: false)],
        animation: .default
    ) private var arsenals: FetchedResults<Arsenal>
    @State private var selectedArsenal: Arsenal?
    @State private var refreshTrigger = UUID()
    @Binding var isEditMode: Bool
    @State private var selectedArsenalIDs: Set<NSManagedObjectID> = []
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Selection toolbar when in edit mode
            if isEditMode && !arsenals.isEmpty {
                SelectionToolbar(
                    selectedCount: selectedArsenalIDs.count,
                    totalCount: arsenals.count,
                    onSelectAll: selectAll,
                    onSelectCompleted: selectCompleted,
                    onDeselectAll: deselectAll,
                    onDelete: { showingDeleteConfirmation = true }
                )
            }
            
            List {
                if arsenals.isEmpty {
                    EmptyStateView()
                } else {
                    ForEach(arsenals, id: \.objectID) { arsenal in
                        if isEditMode {
                            SelectableArsenalRowView(
                                arsenal: arsenal,
                                isSelected: selectedArsenalIDs.contains(arsenal.objectID),
                                onToggleSelection: { toggleSelection(for: arsenal) }
                            )
                        } else {
                            ArsenalRowView(arsenal: arsenal) {
                                selectedArsenal = arsenal
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", role: .destructive) {
                                    _ = arsenalManager.deleteArsenal(arsenal)
                                }
                                
                                Button("Edit") {
                                    selectedArsenal = arsenal
                                }
                                .tint(.blue)
                            }
                        }
                    }
                    .onMove(perform: isEditMode ? nil : moveArsenals)
                }
            }
            .listStyle(PlainListStyle())
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !arsenals.isEmpty {
                    Button(isEditMode ? "Done" : "Select") {
                        withAnimation {
                            isEditMode.toggle()
                            if !isEditMode {
                                selectedArsenalIDs.removeAll()
                            }
                        }
                    }
                }
            }
        }
        .refreshable {
            // Force a refresh of the fetch request
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            refreshTrigger = UUID()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) { _ in
            // Refresh the view when Core Data changes
            DispatchQueue.main.async {
                viewContext.refreshAllObjects()
                refreshTrigger = UUID()
            }
        }
        .sheet(item: $selectedArsenal, onDismiss: {
            // Force refresh when edit sheet is dismissed
            DispatchQueue.main.async {
                viewContext.refreshAllObjects()
                refreshTrigger = UUID()
            }
        }) { arsenal in
            EditArsenalView(arsenal: arsenal)
                .environment(\.managedObjectContext, viewContext)
        }
        .alert("Delete Arsenals", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete \(selectedArsenalIDs.count)", role: .destructive) {
                deleteSelectedArsenals()
            }
        } message: {
            Text("Are you sure you want to delete \(selectedArsenalIDs.count) arsenal\(selectedArsenalIDs.count == 1 ? "" : "s")? This action cannot be undone.")
        }
        .id(refreshTrigger) // Force view refresh when trigger changes
    }
    
    // MARK: - Selection Methods
    private func toggleSelection(for arsenal: Arsenal) {
        if selectedArsenalIDs.contains(arsenal.objectID) {
            selectedArsenalIDs.remove(arsenal.objectID)
        } else {
            selectedArsenalIDs.insert(arsenal.objectID)
        }
    }
    
    private func selectAll() {
        selectedArsenalIDs = Set(arsenals.map { $0.objectID })
    }
    
    private func selectCompleted() {
        selectedArsenalIDs = Set(arsenals.filter { $0.isCompleted }.map { $0.objectID })
    }
    
    private func deselectAll() {
        selectedArsenalIDs.removeAll()
    }
    
    private func deleteSelectedArsenals() {
        let arsenalsToDelete = arsenals.filter { selectedArsenalIDs.contains($0.objectID) }
        _ = arsenalManager.deleteArsenals(Array(arsenalsToDelete))
        selectedArsenalIDs.removeAll()
        
        // Exit edit mode if no arsenals left
        if arsenals.isEmpty {
            isEditMode = false
        }
    }
    
    // MARK: - Drag to Reorder
    private func moveArsenals(from source: IndexSet, to destination: Int) {
        // Convert FetchedResults to array for manipulation
        var arsenalsArray = Array(arsenals)
        arsenalsArray.move(fromOffsets: source, toOffset: destination)
        
        // Update createdDate to maintain the new order
        // Since we sort by createdDate descending, the first item should have the latest date
        let now = Date()
        for (index, arsenal) in arsenalsArray.enumerated() {
            // Subtract seconds based on index to maintain order
            arsenal.createdDate = now.addingTimeInterval(-Double(index))
        }
        
        // Save the context
        do {
            try viewContext.save()
            refreshTrigger = UUID()
            
            // Reload widget to show new order
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            print("Error reordering arsenals: \(error)")
        }
    }
}

// MARK: - Selection Toolbar
struct SelectionToolbar: View {
    let selectedCount: Int
    let totalCount: Int
    let onSelectAll: () -> Void
    let onSelectCompleted: () -> Void
    let onDeselectAll: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Selection info
                Text("\(selectedCount) selected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Selection buttons
                Menu {
                    Button(action: onSelectAll) {
                        Label("Select All", systemImage: "checkmark.circle.fill")
                    }
                    
                    Button(action: onSelectCompleted) {
                        Label("Select Completed", systemImage: "checkmark.circle")
                    }
                    
                    if selectedCount > 0 {
                        Button(action: onDeselectAll) {
                            Label("Deselect All", systemImage: "circle")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Select")
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                }
                
                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(selectedCount > 0 ? .red : .gray)
                }
                .disabled(selectedCount == 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(UIColor.secondarySystemBackground))
            
            Divider()
        }
    }
}

// MARK: - Selectable Arsenal Row
struct SelectableArsenalRowView: View {
    let arsenal: Arsenal
    let isSelected: Bool
    let onToggleSelection: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Selection checkbox
            Button(action: onToggleSelection) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isSelected ? .blue : .gray)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Arsenal content
            VStack(alignment: .leading, spacing: 4) {
                Text(arsenal.title ?? "Untitled Arsenal")
                    .font(.body)
                    .fontWeight(.medium)
                    .strikethrough(arsenal.isCompleted)
                    .foregroundColor(arsenal.isCompleted ? .secondary : .primary)
                
                if let description = arsenal.arsenalDescription, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                // Completion status badge
                if arsenal.isCompleted {
                    Text("Completed")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(4)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onToggleSelection()
        }
    }
}

struct ArsenalRowView: View {
    @EnvironmentObject var arsenalManager: ArsenalManager
    let arsenal: Arsenal
    let onTap: () -> Void
    @State private var isUpdating = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Checkbox
            Button(action: {
                toggleCompletion()
            }) {
                Group {
                    if isUpdating {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: arsenal.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundColor(arsenal.isCompleted ? .green : .gray)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: arsenal.isCompleted)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isUpdating)
            
            // Arsenal content
            VStack(alignment: .leading, spacing: 4) {
                Text(arsenal.title ?? "Untitled Arsenal")
                    .font(.body)
                    .fontWeight(.medium)
                    .strikethrough(arsenal.isCompleted)
                    .foregroundColor(arsenal.isCompleted ? .secondary : .primary)
                
                if let description = arsenal.arsenalDescription, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                // Display notification interval summary
                let config = IntervalConfiguration(from: arsenal)
                if config.type != .none {
                    Text(config.summary)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Notification indicator
            let config = IntervalConfiguration(from: arsenal)
            if config.type != .none && !arsenal.isCompleted {
                Image(systemName: "bell.fill")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
    
    private func toggleCompletion() {
        isUpdating = true
        
        // Small delay to show loading state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            _ = arsenalManager.toggleCompletion(for: arsenal)
            isUpdating = false
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Arsenals Yet")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            Text("Create your first arsenal to get started with managing your tasks.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
