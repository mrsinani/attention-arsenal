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
                .sheet(isPresented: $showingAddArsenal) {
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
                requestNotificationPermission()
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
    
    private func requestNotificationPermission() {
        Task {
            _ = await notificationManager.requestNotificationPermission()
        }
    }
}

struct ArsenalListView: View {
    @EnvironmentObject var arsenalManager: ArsenalManager
    @State private var arsenals: [Arsenal] = []
    
    var body: some View {
        List {
            if arsenals.isEmpty {
                EmptyStateView()
            } else {
                ForEach(arsenals, id: \.objectID) { arsenal in
                    ArsenalRowView(arsenal: arsenal)
                }
                .onDelete(perform: deleteArsenals)
            }
        }
        .listStyle(PlainListStyle())
        .onAppear {
            loadArsenals()
        }
        .refreshable {
            loadArsenals()
        }
    }
    
    private func loadArsenals() {
        arsenals = arsenalManager.fetchArsenals(completed: false)
    }
    
    private func deleteArsenals(offsets: IndexSet) {
        for index in offsets {
            let arsenal = arsenals[index]
            _ = arsenalManager.deleteArsenal(arsenal)
        }
        loadArsenals()
    }
}

struct ArsenalRowView: View {
    @EnvironmentObject var arsenalManager: ArsenalManager
    let arsenal: Arsenal
    @State private var isCompleted: Bool
    
    init(arsenal: Arsenal) {
        self.arsenal = arsenal
        self._isCompleted = State(initialValue: arsenal.isCompleted)
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Checkbox
            Button(action: {
                isCompleted.toggle()
                _ = arsenalManager.toggleCompletion(for: arsenal)
            }) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isCompleted ? .green : .gray)
                    .animation(.easeInOut(duration: 0.2), value: isCompleted)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Arsenal content
            VStack(alignment: .leading, spacing: 4) {
                Text(arsenal.title ?? "Untitled Arsenal")
                    .font(.body)
                    .fontWeight(.medium)
                    .strikethrough(isCompleted)
                    .foregroundColor(isCompleted ? .secondary : .primary)
                
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
            if arsenal.notificationInterval > 0 {
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
