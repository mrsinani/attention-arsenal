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
