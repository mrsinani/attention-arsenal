import SwiftUI

// MARK: - Interval Selection View
struct IntervalSelectionView: View {
    @Binding var intervalConfig: IntervalConfiguration
    let isAuthorized: Bool
    
    var body: some View {
        Section(header: Text("Notifications")) {
            // Interval Type Picker
            Picker("Reminder Type", selection: $intervalConfig.type) {
                ForEach(IntervalType.allCases) { type in
                    HStack {
                        Image(systemName: type.icon)
                        Text(type.displayName)
                    }
                    .tag(type)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: intervalConfig.type) { oldValue, newValue in
                // Reset to defaults when type changes
                intervalConfig = IntervalConfiguration.defaultFor(type: newValue)
            }
            
            // Show configuration options based on selected type
            if intervalConfig.type != .none {
                intervalConfigurationView
            }
            
            // Permission warning
            if intervalConfig.type != .none && !isAuthorized {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("Notification permission required")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    @ViewBuilder
    private var intervalConfigurationView: some View {
        switch intervalConfig.type {
        case .none:
            EmptyView()
            
        case .minutes, .hours:
            // Value picker for minutes/hours
            valuePickerView
            
        case .daily:
            // Time picker
            DatePicker("Time", selection: Binding(
                get: {
                    var components = DateComponents()
                    components.hour = Int(intervalConfig.hour)
                    components.minute = Int(intervalConfig.minute)
                    return Calendar.current.date(from: components) ?? Date()
                },
                set: { date in
                    let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                    intervalConfig.hour = Int16(components.hour ?? 9)
                    intervalConfig.minute = Int16(components.minute ?? 0)
                }
            ), displayedComponents: .hourAndMinute)
            .datePickerStyle(.compact)
            
        case .weekly:
            VStack(alignment: .leading, spacing: 12) {
                // Time picker
                DatePicker("Time", selection: Binding(
                    get: {
                        var components = DateComponents()
                        components.hour = Int(intervalConfig.hour)
                        components.minute = Int(intervalConfig.minute)
                        return Calendar.current.date(from: components) ?? Date()
                    },
                    set: { date in
                        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                        intervalConfig.hour = Int16(components.hour ?? 9)
                        intervalConfig.minute = Int16(components.minute ?? 0)
                    }
                ), displayedComponents: .hourAndMinute)
                .datePickerStyle(.compact)
                
                // Days of week selection
                Text("Days of week")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                WeekdaySelectionView(days: Binding(
                    get: { intervalConfig.days },
                    set: { intervalConfig.days = $0 }
                ))
            }
            
        case .monthly:
            VStack(alignment: .leading, spacing: 12) {
                // Months interval picker
                Picker("Repeat", selection: $intervalConfig.value) {
                    ForEach(Array(intervalConfig.type.availableValues), id: \.self) { value in
                        Text(value == 1 ? "Every month" : "Every \(value) months")
                            .tag(value)
                    }
                }
                .pickerStyle(.menu)
                
                // Calendar grid for day selection
                Text("Days of month")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                MonthDaysSelectionView(monthDays: Binding(
                    get: { intervalConfig.monthDays },
                    set: { intervalConfig.monthDays = $0 }
                ))
                
                // Time picker
                DatePicker("Time", selection: Binding(
                    get: {
                        var components = DateComponents()
                        components.hour = Int(intervalConfig.hour)
                        components.minute = Int(intervalConfig.minute)
                        return Calendar.current.date(from: components) ?? Date()
                    },
                    set: { date in
                        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                        intervalConfig.hour = Int16(components.hour ?? 9)
                        intervalConfig.minute = Int16(components.minute ?? 0)
                    }
                ), displayedComponents: .hourAndMinute)
                .datePickerStyle(.compact)
            }
        }
    }
    
    @ViewBuilder
    private var valuePickerView: some View {
        let availableValues: [Int16] = intervalConfig.type.availableValues
        let typeName = intervalConfig.type.displayName.lowercased()
        Picker("Interval", selection: $intervalConfig.value) {
            ForEach(availableValues, id: \.self) { value in
                Text("Every \(value) \(value == 1 ? String(typeName.dropLast()) : typeName)")
                    .tag(value)
            }
        }
        .pickerStyle(.menu)
    }
}

// MARK: - Month Days Selection View
struct MonthDaysSelectionView: View {
    @Binding var monthDays: MonthDaysBitmask
    
    var body: some View {
        VStack(spacing: 8) {
            // Calendar grid: 7 columns for days 1-31
            let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
            
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(1...31, id: \.self) { day in
                    Button(action: {
                        monthDays.toggle(day)
                    }) {
                        Text("\(day)")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 36, height: 36)
                            .background(monthDays.isSelected(day) ? Color.accentColor : Color.gray.opacity(0.2))
                            .foregroundColor(monthDays.isSelected(day) ? .white : .primary)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Weekday Selection View
struct WeekdaySelectionView: View {
    @Binding var days: DaysBitmask
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(Weekday.allCases) { weekday in
                Button(action: {
                    days.toggle(weekday)
                }) {
                    VStack(spacing: 4) {
                        Text(weekday.shortName)
                            .font(.system(size: 12, weight: .medium))
                        Text(weekday.fullName.prefix(3))
                            .font(.system(size: 10))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(days.isSelected(weekday) ? Color.accentColor : Color.gray.opacity(0.2))
                    .foregroundColor(days.isSelected(weekday) ? .white : .primary)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    Form {
        IntervalSelectionView(
            intervalConfig: .constant(IntervalConfiguration.defaultDaily),
            isAuthorized: true
        )
    }
}
