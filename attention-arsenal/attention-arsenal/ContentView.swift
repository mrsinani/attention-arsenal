import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var arsenalManager = ArsenalManager()
    @EnvironmentObject var notificationManager: NotificationManager
    @State private var showingAddArsenal = false
    @State private var showingNotificationPermissionAlert = false
    
    var body: some View {
        NavigationView {
            ArsenalListView()
                .navigationTitle("Attention Arsenal")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            showingAddArsenal = true
                        }) {
                            Image(systemName: "plus")
                                .font(.title2)
                                .foregroundColor(.primary)
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
        }
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
    
    var body: some View {
        List {
            if arsenals.isEmpty {
                EmptyStateView()
            } else {
                ForEach(arsenals, id: \.objectID) { arsenal in
                    ArsenalRowView(arsenal: arsenal)
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
        }
        .listStyle(PlainListStyle())
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
        .id(refreshTrigger) // Force view refresh when trigger changes
    }
}

struct ArsenalRowView: View {
    @EnvironmentObject var arsenalManager: ArsenalManager
    let arsenal: Arsenal
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
                
                if let dueDate = arsenal.dueDate {
                    Text(dueDate, style: .date)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Notification indicator
            if arsenal.notificationInterval > 0 && !arsenal.isCompleted {
                Image(systemName: "bell.fill")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            // TODO: Navigate to edit view
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
