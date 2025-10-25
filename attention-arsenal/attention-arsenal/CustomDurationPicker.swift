import SwiftUI

struct CustomDurationPicker: View {
    @Binding var customValue: Int32
    @Binding var customUnit: DurationUnit
    @Binding var selectedInterval: NotificationInterval
    @State private var inputText: String
    @State private var showingOverflowAlert = false
    
    init(customValue: Binding<Int32>, customUnit: Binding<DurationUnit>, selectedInterval: Binding<NotificationInterval>) {
        self._customValue = customValue
        self._customUnit = customUnit
        self._selectedInterval = selectedInterval
        
        // Initialize text field - show empty if 0
        if customValue.wrappedValue == 0 {
            self._inputText = State(initialValue: "")
        } else {
            self._inputText = State(initialValue: "\(customValue.wrappedValue)")
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Number input
            TextField("Value", text: $inputText)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .onChange(of: inputText) { oldValue, newValue in
                    validateAndUpdateValue(newValue)
                }
            
            // Unit picker
            Picker("", selection: $customUnit) {
                ForEach(DurationUnit.allCases) { unit in
                    Text(unit.rawValue).tag(unit)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: customUnit) { oldValue, newValue in
                // Reset value to 1 when unit changes to prevent overflow
                customValue = 1
                inputText = "1"
            }
        }
        .alert("Value Too Large", isPresented: $showingOverflowAlert) {
            Button("OK") {
                // Reset to max allowed value
                let maxValue = customUnit.maxValue
                customValue = maxValue
                inputText = "\(maxValue)"
            }
        } message: {
            Text("The maximum value for \(customUnit.rawValue.lowercased()) is \(customUnit.maxValue). The value has been adjusted.")
        }
    }
    
    private func validateAndUpdateValue(_ text: String) {
        // Remove any non-digit characters
        let filtered = text.filter { $0.isNumber }
        
        // If empty, set to 0 but keep custom selected
        guard !filtered.isEmpty else {
            customValue = 0
            return
        }
        
        // Try to parse as Int32
        guard let value = Int32(filtered) else {
            // If parsing fails, it's too large
            showingOverflowAlert = true
            return
        }
        
        // Skip validation for 0 (it's always valid)
        if value == 0 {
            customValue = 0
            if inputText != filtered {
                inputText = filtered
            }
            return
        }
        
        // Check against unit-specific max
        let maxForUnit = customUnit.maxValue
        if value > maxForUnit {
            showingOverflowAlert = true
            return
        }
        
        // Check if total minutes would overflow
        let multiplier = customUnit.minutesMultiplier
        let (result, overflow) = value.multipliedReportingOverflow(by: multiplier)
        
        if overflow || result <= 0 {
            showingOverflowAlert = true
            return
        }
        
        // All validations passed
        customValue = value
        
        // Update text field to show only digits
        if inputText != filtered {
            inputText = filtered
        }
    }
}

// Helper view for the notification interval section
struct NotificationIntervalSection: View {
    @Binding var selectedInterval: NotificationInterval
    @Binding var customMinutes: Int32
    @Binding var customValue: Int32
    @Binding var customUnit: DurationUnit
    let isAuthorized: Bool
    
    var body: some View {
        Section(header: Text("Notifications")) {
            Picker("Reminder Interval", selection: $selectedInterval) {
                ForEach(NotificationInterval.allCases, id: \.self) { interval in
                    Text(interval.displayName)
                        .tag(interval)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedInterval) { oldValue, newValue in
                // When switching from custom, save the custom duration
                if oldValue == .custom && newValue != .custom {
                    // No need to do anything, just switch
                } else if newValue == .custom {
                    // Initialize custom duration if needed
                    if customValue == 0 {
                        customValue = 1
                        customUnit = .days
                    }
                }
            }
            
            // Show custom duration picker when "Custom" is selected
            if selectedInterval == .custom {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom Interval")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    CustomDurationPicker(
                        customValue: $customValue,
                        customUnit: $customUnit,
                        selectedInterval: $selectedInterval
                    )
                    .onChange(of: customValue) { _, _ in
                        updateCustomMinutes()
                    }
                    .onChange(of: customUnit) { _, _ in
                        updateCustomMinutes()
                    }
                    
                    // Show total duration
                    if customMinutes > 0 {
                        Text(formatDuration(minutes: customMinutes))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("No notifications")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Permission warning
            if selectedInterval != .none && !isAuthorized {
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
    
    private func updateCustomMinutes() {
        // Use overflow-safe multiplication
        let (result, overflow) = customValue.multipliedReportingOverflow(by: customUnit.minutesMultiplier)
        
        if overflow {
            // If overflow detected, cap at Int32 max safely
            customMinutes = Int32.max / 2 // Use half of max to be extra safe
        } else {
            customMinutes = result
        }
    }
    
    private func formatDuration(minutes: Int32) -> String {
        if minutes < 60 {
            return "Repeats every \(minutes) minute\(minutes == 1 ? "" : "s")"
        } else if minutes < 1440 {
            let hours = minutes / 60
            return "Repeats every \(hours) hour\(hours == 1 ? "" : "s")"
        } else if minutes < 10080 {
            let days = minutes / 1440
            return "Repeats every \(days) day\(days == 1 ? "" : "s")"
        } else if minutes < 43200 {
            let weeks = minutes / 10080
            return "Repeats every \(weeks) week\(weeks == 1 ? "" : "s")"
        } else {
            let months = minutes / 43200
            return "Repeats every ~\(months) month\(months == 1 ? "" : "s")"
        }
    }
}

#Preview {
    @Previewable @State var customValue: Int32 = 1
    @Previewable @State var customUnit: DurationUnit = .days
    @Previewable @State var selectedInterval: NotificationInterval = .custom
    
    Form {
        CustomDurationPicker(customValue: $customValue, customUnit: $customUnit, selectedInterval: $selectedInterval)
    }
}

