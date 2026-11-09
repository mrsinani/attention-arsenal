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
    @State private var renamingCategory: String?
    @State private var renameText = ""

    /// Newline-joined names of the category headers the user has opened. Everything else is
    /// collapsed, which makes collapsed the default for new categories. Names can't contain a
    /// newline (they come from a single-line TextField).
    @AppStorage("expandedArsenalCategories") private var expandedCategoriesRaw = ""
    private var expandedCategories: Set<String> {
        Set(expandedCategoriesRaw.split(separator: "\n").map(String.init))
    }

    /// The rows matching the filter. Selection and counts operate on this, not the raw fetch.
    private var visibleArsenals: [Arsenal] {
        arsenals.filter { nudgeFilter.matches($0) }
    }

    /// Sort keys for categories (see ArsenalOutline), JSON `[name: key]`.
    @AppStorage("arsenalCategoryOrder") private var categoryKeysRaw = ""
    private var categoryKeys: [String: Double] {
        (try? JSONDecoder().decode([String: Double].self, from: Data(categoryKeysRaw.utf8))) ?? [:]
    }
    private func setCategoryKeys(_ keys: [String: Double]) {
        if let data = try? JSONEncoder().encode(keys) {
            categoryKeysRaw = String(decoding: data, as: UTF8.self)
        }
    }

    private typealias Outline = ArsenalOutline<NSManagedObjectID>

    private var outline: Outline {
        Outline(
            arsenals: arsenals.map {
                ($0.objectID, $0.category, $0.createdDate?.timeIntervalSinceReferenceDate ?? 0)
            },
            categoryKeys: categoryKeys
        )
    }

    private var arsenalsByID: [NSManagedObjectID: Arsenal] {
        Dictionary(uniqueKeysWithValues: arsenals.map { ($0.objectID, $0) })
    }

    /// Select mode opens every group, so "Select All" never reaches rows you can't see.
    private func isExpanded(_ category: String) -> Bool {
        isEditMode || expandedCategories.contains(category)
    }

    private func toggleExpanded(_ category: String) {
        guard !isEditMode else { return }
        var set = expandedCategories
        if set.contains(category) { set.remove(category) } else { set.insert(category) }
        expandedCategoriesRaw = set.sorted().joined(separator: "\n")
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
                    let visibleIDs = Set(visibleArsenals.map(\.objectID))
                    let byID = arsenalsByID
                    let outline = self.outline
                    let rows = outline.rows(isVisible: visibleIDs.contains, isExpanded: isExpanded)
                    // One ForEach over arsenals AND category headers, so either can be held
                    // and dragged anywhere, including a category between two arsenals.
                    ForEach(rows) { row in
                        switch row {
                        case .header(let category):
                            categoryRow(category, count: (outline.children[category] ?? []).filter(visibleIDs.contains).count)
                        case .arsenal(let arsenalID, let category):
                            if let arsenal = byID[arsenalID] {
                                arsenalRow(arsenal)
                                    // Arsenals inside a category are indented under it.
                                    .padding(.leading, category == nil ? 0 : 22)
                            }
                        }
                    }
                    .onMove(perform: isEditMode ? nil : { moveRow(rows, from: $0, to: $1) })
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
        .alert("Rename Category", isPresented: Binding(
            get: { renamingCategory != nil },
            set: { if !$0 { renamingCategory = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { }
            Button("Rename") {
                let name = Arsenal.cleanCategoryName(renameText)
                if let old = renamingCategory, !name.isEmpty {
                    recategorize(old, to: name)
                }
            }
        }
    }

    private func categoryRow(_ category: String, count: Int) -> some View {
        CategoryHeader(
            name: category,
            count: count,
            isExpanded: isExpanded(category),
            onToggle: { withAnimation(.snappy(duration: 0.25)) { toggleExpanded(category) } },
            onRename: {
                renameText = category
                renamingCategory = category
            },
            onRemove: { withAnimation(.snappy) { recategorize(category, to: nil) } }
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Remove", role: .destructive) {
                withAnimation(.snappy) { recategorize(category, to: nil) }
            }
            Button("Rename") {
                renameText = category
                renamingCategory = category
            }
            .tint(.blue)
        }
    }

    @ViewBuilder
    private func arsenalRow(_ arsenal: Arsenal) -> some View {
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
    /// Moves one row (arsenal or category) and rewrites every sort key from the new order.
    /// The outline holds all arsenals, including ones the filter hides, so they keep their place.
    private func moveRow(_ rows: [Outline.Row], from source: IndexSet, to destination: Int) {
        guard let from = source.first else { return }
        let prev = rows.indices.last { $0 < destination && $0 != from }.map { rows[$0] }
        let next = rows.indices.first { $0 >= destination && $0 != from }.map { rows[$0] }
        var outline = self.outline
        outline.move(rows[from], prev: prev, next: next)

        let byID = arsenalsByID
        let base = Date().timeIntervalSinceReferenceDate
        var keys: [String: Double] = [:]
        for (index, item) in outline.flatOrder.enumerated() {
            let key = base - Double(index)
            switch item {
            case .arsenal(let id): byID[id]?.createdDate = Date(timeIntervalSinceReferenceDate: key)
            case .category(let name): keys[name] = key
            }
        }
        for (id, category) in outline.categoryByArsenal where byID[id]?.category != category {
            byID[id]?.category = category
        }
        setCategoryKeys(keys)

        do {
            try viewContext.save()
            // Widget lists arsenals by createdDate, so it follows the new order.
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            print("Error reordering arsenals: \(error)")
        }
    }

    // MARK: - Categories
    /// Rename (`to: name`) or remove (`to: nil`) a category. Removing never deletes arsenals:
    /// their sort keys sit right under the category's, so they stay in the same spot, now
    /// top level, and keep firing as before.
    private func recategorize(_ old: String, to new: String?) {
        for arsenal in arsenals where arsenal.category == old {
            arsenal.category = new
        }
        var expanded = expandedCategories
        if expanded.remove(old) != nil, let new { expanded.insert(new) }
        expandedCategoriesRaw = expanded.sorted().joined(separator: "\n")

        var keys = categoryKeys
        let oldKey = keys.removeValue(forKey: old)
        if let new, keys[new] == nil { keys[new] = oldKey }
        setCategoryKeys(keys)

        do {
            try viewContext.save()
        } catch {
            print("Error updating category: \(error)")
        }
    }
}

/// Category row: tap the name or chevron to collapse, ••• or swipe for rename/remove, hold to
/// drag. No context menu: long-press is the drag gesture. Separate borderless buttons so each
/// part gets its own tap target inside the row.
struct CategoryHeader: View {
    let name: String
    let count: Int
    let isExpanded: Bool
    let onToggle: () -> Void
    let onRename: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Text(name)
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                    Text("\(count)")
                        .font(.subheadline)
                        .foregroundStyle(Color(.secondaryLabel))
                        .contentTransition(.numericText())
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            Menu {
                actions
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.secondaryLabel))
                    .frame(width: 36, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(name) options")

            Button(action: onToggle) {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(.secondaryLabel))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 28, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isExpanded ? "Collapse \(name)" : "Expand \(name)")
        }
        .textCase(nil)
        .tint(Color(.secondaryLabel))
        .padding(.top, 10)
        .padding(.bottom, 2)
        .sensoryFeedback(.selection, trigger: isExpanded)
    }

    @ViewBuilder private var actions: some View {
        Button(action: onRename) {
            Label("Rename", systemImage: "pencil")
        }
        Button(role: .destructive, action: onRemove) {
            Label("Remove Category", systemImage: "folder.badge.minus")
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
