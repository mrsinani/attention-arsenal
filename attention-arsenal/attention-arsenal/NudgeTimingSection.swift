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
