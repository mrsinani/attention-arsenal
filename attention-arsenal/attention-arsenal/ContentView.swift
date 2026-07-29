import SwiftUI
import CoreData
import WidgetKit

/// Capsule background for the centered toolbar buttons. A `.principal` toolbar item is a plain
/// custom view, so it doesn't pick up the system's automatic Liquid Glass pill the way regular
/// leading/trailing toolbar items do — we apply it ourselves.
private struct ToolbarPill: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // GlassEffectContainer owns the morph animation when a child presents/dismisses
            // (the filter Menu). Without it the effect is re-created on dismiss and can land
            // on the default rounded-rect shape instead of the capsule. The outer clipShape is
            // a belt-and-braces guard so the pill can never render square mid-transition.
            GlassEffectContainer {
                content.glassEffect(.regular, in: .capsule)
            }
            .clipShape(Capsule())
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var arsenalManager = ArsenalManager()
    @EnvironmentObject var notificationManager: NotificationManager
    @State private var showingAddArsenal = false
    @State private var showingNotificationPermissionAlert = false
    @State private var showingSettings = false
    @State private var showingStats = false
    @State private var isEditMode = false

    /// Persisted so the list opens on whichever filter you last used.
    @AppStorage("arsenalNudgeFilter") private var nudgeFilterRaw = NudgeFilter.all.rawValue
    private var nudgeFilter: NudgeFilter { NudgeFilter(rawValue: nudgeFilterRaw) ?? .all }

    /// Only used to decide whether the Select button belongs in the toolbar. The list itself
    /// has its own fetch request; this one just needs to know empty vs not.
    @FetchRequest(sortDescriptors: []) private var arsenals: FetchedResults<Arsenal>

    /// Select is pointless when the active filter hides everything.
    private var hasVisibleArsenals: Bool { arsenals.contains { nudgeFilter.matches($0) } }

    var body: some View {
        NavigationView {
            ArsenalListView(isEditMode: $isEditMode, nudgeFilter: nudgeFilter)
                // Centered .principal pill in the bar, with the large title on its own row below.
                .navigationTitle("Attention Arsenal")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    // One ToolbarItem holding an HStack: .principal renders a single view, so a
                    // ToolbarItemGroup here would drop everything after the first button.
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 22) {
                            Button(action: {
                                showingSettings = true
                            }) {
                                Image(systemName: "gearshape")
                                    .font(.title2)
                                    .foregroundColor(.primary)
                            }

                            Button(action: {
                                showingStats = true
                            }) {
                                Image(systemName: "chart.bar.fill")
                                    .font(.title2)
                                    .foregroundColor(.primary)
                            }

                            Menu {
                                Picker("Filter", selection: $nudgeFilterRaw) {
                                    ForEach(NudgeFilter.allCases) { filter in
                                        Label(filter.label, systemImage: filter.icon)
                                            .tag(filter.rawValue)
                                    }
                                }
                            } label: {
                                HStack(spacing: 3) {
                                    Text(nudgeFilter.shortLabel)
                                    Image(systemName: "chevron.down")
                                        .font(.caption2.weight(.semibold))
                                }
                                .foregroundColor(.primary)
                            }

                            if !isEditMode {
                                Button(action: {
                                    showingAddArsenal = true
                                }) {
                                    Image(systemName: "plus")
                                        .font(.title2)
                                        .foregroundColor(.primary)
                                }
                            }

                            if hasVisibleArsenals {
                                Button(isEditMode ? "Done" : "Select") {
                                    withAnimation {
                                        isEditMode.toggle()
                                    }
                                }
                                .foregroundColor(.primary)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .modifier(ToolbarPill())
                    }
                }
                // ArsenalManager saves on this same viewContext, so @FetchRequest inserts the
                // new row on its own — no manual refresh needed on dismiss.
                .sheet(isPresented: $showingAddArsenal) {
                    AddArsenalView()
                        .environment(\.managedObjectContext, viewContext)
                }
                .sheet(isPresented: $showingSettings) {
                    SettingsView()
                }
                .sheet(isPresented: $showingStats) {
                    StatsView()
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
    @Binding var isEditMode: Bool
    let nudgeFilter: NudgeFilter
    @State private var selectedArsenalIDs: Set<NSManagedObjectID> = []
    @State private var showingDeleteConfirmation = false

    /// The rows actually on screen. Everything below operates on this, not the raw fetch,
    /// so selection and counts stay consistent with what the filter is showing.
    private var visibleArsenals: [Arsenal] {
        arsenals.filter { nudgeFilter.matches($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Selection toolbar when in edit mode
            if isEditMode && !visibleArsenals.isEmpty {
                SelectionToolbar(
                    selectedCount: selectedArsenalIDs.count,
                    totalCount: visibleArsenals.count,
                    onSelectAll: selectAll,
                    onSelectCompleted: selectCompleted,
                    onDeselectAll: deselectAll,
                    onDelete: { showingDeleteConfirmation = true }
                )
            }
            
            List {
                if visibleArsenals.isEmpty {
                    EmptyStateView(filter: nudgeFilter)
                } else {
                    ForEach(visibleArsenals, id: \.objectID) { arsenal in
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
                    // ponytail: reordering is disabled while a filter is active — moveArsenals
                    // rewrites createdDate across the whole fetch, so indices from a filtered
                    // ForEach would reorder the wrong rows. Switch to All to reorder.
                    .onMove(perform: (isEditMode || nudgeFilter != .all) ? nil : moveArsenals)
                }
            }
            .listStyle(PlainListStyle())
        }
        // Select/Done now lives in ContentView's centered toolbar pill; clear the selection
        // here when edit mode turns off so this view keeps owning its own selection state.
        .onChange(of: isEditMode) { _, editing in
            if !editing {
                selectedArsenalIDs.removeAll()
            }
        }
        .refreshable {
            // Re-read from the store; the fetch request itself is already live.
            viewContext.refreshAllObjects()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) { note in
            // Saves made on this context are picked up automatically by @FetchRequest and the
            // rows' @ObservedObject. Only a save from *another* context (Siri intents, widget)
            // needs a manual fault-in, so skip the churn for local saves.
            guard let savedContext = note.object as? NSManagedObjectContext,
                  savedContext !== viewContext else { return }
            DispatchQueue.main.async {
                viewContext.refreshAllObjects()
            }
        }
        .sheet(item: $selectedArsenal) { arsenal in
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
        selectedArsenalIDs = Set(visibleArsenals.map { $0.objectID })
    }

    private func selectCompleted() {
        selectedArsenalIDs = Set(visibleArsenals.filter { $0.isCompleted }.map { $0.objectID })
    }
    
    private func deselectAll() {
        selectedArsenalIDs.removeAll()
    }
    
    private func deleteSelectedArsenals() {
        let arsenalsToDelete = arsenals.filter { selectedArsenalIDs.contains($0.objectID) }
        _ = arsenalManager.deleteArsenals(Array(arsenalsToDelete))
        selectedArsenalIDs.removeAll()
        
        // Exit edit mode if no arsenals left
        if visibleArsenals.isEmpty {
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
    @ObservedObject var arsenal: Arsenal
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
    // @ObservedObject so the row redraws itself when its own fields change (e.g. isCompleted).
    // Without this the list needed a blunt .id() refresh that rebuilt every row on any save.
    @ObservedObject var arsenal: Arsenal
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
                    Text(config.summary(notificationStartDate: arsenal.notificationStartDate))
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
    var filter: NudgeFilter = .all

    private var title: String {
        filter == .all ? "No Arsenals Yet" : "Nothing \(filter.label)"
    }

    private var message: String {
        switch filter {
        case .all:
            return "Create your first arsenal to get started with managing your tasks."
        case .now:
            return "No arsenals are nudging right now. Switch the filter to All to see the rest."
        case .later:
            return "No arsenals are waiting on a later start. Switch the filter to All to see the rest."
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: filter == .all ? "list.bullet.clipboard" : filter.icon)
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text(title)
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.primary)

            Text(message)
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
