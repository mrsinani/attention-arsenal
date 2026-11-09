import SwiftUI

enum NudgeTiming: String, CaseIterable, Identifiable {
    case now
    case later

    var id: String { rawValue }

    var label: String {
        switch self {
        case .now: return "Nudge me now"
        case .later: return "Nudge me later"
        }
    }
}

/// Marks an arsenal's notifications time-sensitive so they cut through Focus and the
/// Scheduled Summary. Shared by the create and edit forms so both stay in step.
struct ImportantToggleSection: View {
    @Binding var isImportant: Bool

    var body: some View {
        Section {
            Toggle(isOn: $isImportant) {
                Label("Mark as important", systemImage: "exclamationmark.circle")
            }
        } footer: {
            Text("Important reminders break through Focus and Do Not Disturb, and skip the Scheduled Summary. Use it for things you can't miss, like medication.")
        }
    }
}

/// Per-arsenal opt-out of Settings → Quiet Hours. Only shown for "every X minutes/hours"
/// nudges; reminders at a time you picked fire at that time regardless.
struct QuietHoursToggleSection: View {
    @Binding var respectsQuietHours: Bool
    let intervalType: IntervalType
    @AppStorage(QuietHours.enabledKey) private var quietHoursEnabled = false
    @AppStorage(QuietHours.startKey) private var start = QuietHours.defaultStart
    @AppStorage(QuietHours.endKey) private var end = QuietHours.defaultEnd

    var body: some View {
        if intervalType == .minutes || intervalType == .hours {
            Section {
                Toggle(isOn: $respectsQuietHours) {
                    Label("Respect quiet hours", systemImage: "moon")
                }
            } footer: {
                Text(quietHoursEnabled
                     ? "Pauses these nudges during \(QuietHours(start: start, end: end).displayText), then resumes when quiet hours end."
                     : "Quiet hours are off. Turn them on in Settings to pause nudges overnight.")
            }
        }
    }
}

/// Groups an arsenal under a collapsible header on the main list. Purely visual — it never
/// changes what fires or when. "" means no category.
struct CategoryPickerSection: View {
    @Binding var category: String
    // ponytail: categories are just the distinct names in use, no Category entity. A category
    // disappears once nothing is in it; add an entity if empty categories need to persist.
    @FetchRequest(sortDescriptors: []) private var arsenals: FetchedResults<Arsenal>
    @State private var isAddingNew = false
    @State private var newCategoryName = ""
    @FocusState private var newFieldFocused: Bool

    private var options: [String] {
        Arsenal.categoryNames(in: Array(arsenals), plus: category)
    }

    var body: some View {
        Section("Category") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("None", isSelected: category.isEmpty) { category = "" }
                    ForEach(options, id: \.self) { name in
                        chip(name, isSelected: category == name) { category = name }
                    }
                    if isAddingNew {
                        TextField("Name", text: $newCategoryName)
                            .focused($newFieldFocused)
                            .submitLabel(.done)
                            .onSubmit(commitNew)
                            .font(.subheadline)
                            .frame(minWidth: 90)
                            .fixedSize()
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .overlay(Capsule().strokeBorder(Color.accentColor, lineWidth: 1))
                    } else {
                        chip("New", systemImage: "plus", isSelected: false) {
                            newCategoryName = ""
                            isAddingNew = true
                            newFieldFocused = true
                        }
                    }
                }
                .padding(.vertical, 2)
                .animation(.snappy(duration: 0.2), value: category)
                .animation(.snappy(duration: 0.2), value: isAddingNew)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .sensoryFeedback(.selection, trigger: category)
        }
        // Tapping away from the field keeps whatever was typed, like Reminders' inline add.
        .onChange(of: newFieldFocused) { _, focused in
            if !focused && isAddingNew { commitNew() }
        }
    }

    private func commitNew() {
        let name = Arsenal.cleanCategoryName(newCategoryName)
        if !name.isEmpty { category = name }
        isAddingNew = false
    }

    private func chip(_ title: String, systemImage: String? = nil, isSelected: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage).font(.caption.weight(.semibold))
                }
                Text(title)
            }
            .font(.subheadline.weight(isSelected ? .semibold : .regular))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(isSelected ? Color.accentColor : Color(.tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension Arsenal {
    /// Sorted, de-duplicated category names used by `arsenals` (plus `extra`, so a just-typed
    /// name shows in the picker before it's saved).
    static func categoryNames(in arsenals: [Arsenal], plus extra: String = "") -> [String] {
        Set(arsenals.compactMap(\.category) + [extra])
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func cleanCategoryName(_ raw: String) -> String {
        String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
    }
}

/// Toolbar filter for the arsenal list.
enum NudgeFilter: String, CaseIterable, Identifiable {
    case all
    case now
    case later

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All Arsenals"
        case .now: return "Nudging Now"
        case .later: return "Nudging Later"
        }
    }

    var icon: String {
        switch self {
        case .all: return "tray.full"
        case .now: return "bell.badge"
        case .later: return "clock"
        }
    }

    /// Shown on the toolbar button itself, where the full label would blow out the pill width.
    var shortLabel: String {
        switch self {
        case .all: return "All"
        case .now: return "Now"
        case .later: return "Later"
        }
    }

    func matches(_ arsenal: Arsenal) -> Bool {
        switch self {
        case .all:
            return true
        case .now:
            return isNudging(arsenal)
                && NudgeTimingSection.timing(from: arsenal.notificationStartDate) == .now
        case .later:
            return isNudging(arsenal)
                && NudgeTimingSection.timing(from: arsenal.notificationStartDate) == .later
        }
    }

    /// Only arsenals that will actually fire count as nudging: a completed arsenal has had its
    /// notifications cancelled, and `.none` has no schedule at all.
    private func isNudging(_ arsenal: Arsenal) -> Bool {
        !arsenal.isCompleted && IntervalConfiguration(from: arsenal).type != .none
    }
}

struct NudgeTimingSection: View {
    @Binding var nudgeTiming: NudgeTiming
    @Binding var notificationStartDate: Date

    var body: some View {
        Section {
            Picker("When to nudge", selection: $nudgeTiming) {
                ForEach(NudgeTiming.allCases) { timing in
                    Text(timing.label).tag(timing)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            if nudgeTiming == .later {
                DatePicker(
                    "Starts",
                    selection: $notificationStartDate,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
            }
        }
    }

    /// Default start: tomorrow at 9:00 AM.
    static func defaultStartDate() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    /// Derive tab selection from a persisted start date.
    static func timing(from notificationStartDate: Date?) -> NudgeTiming {
        guard let start = notificationStartDate, start > Date() else { return .now }
        return .later
    }
}
