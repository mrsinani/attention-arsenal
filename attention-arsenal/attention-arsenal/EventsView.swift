import SwiftUI
import EventKit
import CoreData

struct EventsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var calendarManager = CalendarManager.shared
    @StateObject private var arsenalManager: ArsenalManager
    @State private var selectedRange: EventTimeRange = .nextWeek
    @State private var showingPermissionAlert = false
    @State private var isLoading = false
    
    init() {
        let manager = ArsenalManager()
        _arsenalManager = StateObject(wrappedValue: manager)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Time range picker
                Picker("Time Range", selection: $selectedRange) {
                    ForEach(EventTimeRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.menu)
                .padding()
                .onChange(of: selectedRange) { _, _ in
                    loadEvents()
                }
                
                Divider()
                
                // Content
                if !calendarManager.isAuthorized {
                    CalendarPermissionView(
                        onRequestPermission: {
                            Task {
                                await requestPermission()
                            }
                        }
                    )
                } else if isLoading {
                    ProgressView("Loading events...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if calendarManager.events.isEmpty {
                    EmptyEventsView(range: selectedRange)
                } else {
                    EventsList(
                        events: calendarManager.events,
                        arsenalManager: arsenalManager
                    )
                }
            }
            .navigationTitle("Events")
            .navigationBarTitleDisplayMode(.large)
            .task {
                // Load events when view appears
                if calendarManager.isAuthorized {
                    loadEvents()
                }
            }
        }
        .navigationViewStyle(.stack)
    }
    
    private func requestPermission() async {
        isLoading = true
        let granted = await calendarManager.requestCalendarAccess()
        
        if granted {
            await calendarManager.fetchEvents(for: selectedRange)
        }
        
        isLoading = false
    }
    
    private func loadEvents() {
        isLoading = true
        Task {
            await calendarManager.fetchEvents(for: selectedRange)
            isLoading = false
        }
    }
}

// MARK: - Calendar Permission View

struct CalendarPermissionView: View {
    let onRequestPermission: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            VStack(spacing: 12) {
                Text("Calendar Access Required")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("This app needs access to your calendar to display your upcoming events.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Button(action: onRequestPermission) {
                Text("Grant Access")
                    .fontWeight(.semibold)
                    .frame(maxWidth: 200)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            
            Text("You can change this later in Settings")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Events List

struct EventsList: View {
    let events: [EKEvent]
    let arsenalManager: ArsenalManager
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Arsenal.createdDate, ascending: false)],
        animation: .default
    ) private var arsenals: FetchedResults<Arsenal>
    
    var body: some View {
        List {
            ForEach(groupedEvents, id: \.date) { group in
                Section(header: Text(group.title)) {
                    ForEach(group.events, id: \.eventIdentifier) { event in
                        if !hasMatchingArsenal(for: event) {
                            EventRow(
                                event: event,
                                arsenalManager: arsenalManager,
                                onReminderCreated: { }
                            )
                        }
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
    }
    
    // Check if an event already has a matching arsenal
    private func hasMatchingArsenal(for event: EKEvent) -> Bool {
        // Check if any arsenal has an end date matching this event's end date
        // (within 1 hour tolerance to account for variations)
        return arsenals.contains { arsenal in
            guard let arsenalEndDate = arsenal.endDate else { return false }
            
            // Compare end dates within 1 hour tolerance
            let timeDifference = abs(arsenalEndDate.timeIntervalSince(event.endDate))
            return timeDifference < 3600 // Within 1 hour
        }
    }
    
    // Group events by day
    private var groupedEvents: [EventGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: events) { event in
            calendar.startOfDay(for: event.startDate)
        }
        
        return grouped.map { date, events in
            EventGroup(date: date, events: events)
        }.sorted { $0.date < $1.date }
    }
}

struct EventGroup {
    let date: Date
    let events: [EKEvent]
    
    var title: String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let eventDate = calendar.startOfDay(for: date)
        
        if eventDate == today {
            return "Today"
        } else if eventDate == calendar.date(byAdding: .day, value: 1, to: today) {
            return "Tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }
}

// MARK: - Event Row

struct EventRow: View {
    let event: EKEvent
    let arsenalManager: ArsenalManager
    let onReminderCreated: () -> Void
    
    @State private var isCreatingReminder = false
    @State private var showSuccessMessage = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var isHidden = false
    
    var body: some View {
        if !isHidden {
            eventContent
        }
    }
    
    private var eventContent: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                // Color indicator from calendar
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(cgColor: event.calendar.cgColor))
                    .frame(width: 4)
                
                VStack(alignment: .leading, spacing: 6) {
                    // Event title
                    Text(event.title ?? "Untitled Event")
                        .font(.body)
                        .fontWeight(.medium)
                    
                    // Time
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption)
                        
                        if event.isAllDay {
                            Text("All Day")
                                .font(.caption)
                        } else {
                            Text(timeString(for: event))
                                .font(.caption)
                        }
                    }
                    .foregroundColor(.secondary)
                    
                    // Location
                    if let location = event.location, !location.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "location")
                                .font(.caption)
                            Text(location)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .foregroundColor(.secondary)
                    }
                    
                    // Calendar name
                    Text(event.calendar.title)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(cgColor: event.calendar.cgColor).opacity(0.2))
                        .foregroundColor(Color(cgColor: event.calendar.cgColor))
                        .cornerRadius(4)
                }
                
                Spacer()
                
                // Add Reminder Button
                Button(action: {
                    createAIReminder()
                }) {
                    if isCreatingReminder {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if showSuccessMessage {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title3)
                    } else {
                        VStack(spacing: 2) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                            Text("Add")
                                .font(.caption2)
                        }
                        .foregroundColor(.blue)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isCreatingReminder || showSuccessMessage)
            }
            .padding(.vertical, 4)
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func timeString(for event: EKEvent) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        
        let startTime = formatter.string(from: event.startDate)
        let endTime = formatter.string(from: event.endDate)
        
        return "\(startTime) - \(endTime)"
    }
    
    /// Convert minutes to appropriate IntervalConfiguration
    private func convertMinutesToIntervalConfig(_ minutes: Int32) -> IntervalConfiguration {
        switch minutes {
        case 5, 15, 30:
            return IntervalConfiguration(type: .minutes, value: Int16(minutes))
        case 60, 120, 240, 360, 720:
            return IntervalConfiguration(type: .hours, value: Int16(minutes / 60))
        case 1440: // Daily
            return IntervalConfiguration.defaultDaily
        case 10080, 20160: // Weekly or Biweekly (use weekly)
            return IntervalConfiguration.defaultWeekly
        case 43200: // Monthly (approximate)
            return IntervalConfiguration.defaultMonthly
        default:
            // Default to 4 hours
            return IntervalConfiguration(type: .hours, value: 4)
        }
    }
    
    private func createAIReminder() {
        isCreatingReminder = true
        
        Task {
            do {
                // Generate reminder using AI
                let suggestion = try await AIReminderService.shared.generateReminder(for: event)
                
                // Create the arsenal with suggested details
                await MainActor.run {
                    // Convert notification interval (in minutes) to IntervalConfiguration
                    let intervalConfig = convertMinutesToIntervalConfig(suggestion.notificationInterval)
                    
                    let arsenal = arsenalManager.createArsenal(
                        title: suggestion.title,
                        description: suggestion.description,
                        intervalConfig: intervalConfig
                    )
                    
                    isCreatingReminder = false
                    
                    if arsenal != nil {
                        // Show success briefly
                        showSuccessMessage = true
                        
                        // Hide the event after showing success
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation {
                                isHidden = true
                            }
                            onReminderCreated()
                        }
                    } else {
                        errorMessage = "Failed to create reminder"
                        showErrorAlert = true
                    }
                }
            } catch {
                await MainActor.run {
                    isCreatingReminder = false
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
            }
        }
    }
}

// MARK: - Empty State

struct EmptyEventsView: View {
    let range: EventTimeRange
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Events")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("You don't have any events scheduled for \(range.rawValue.lowercased()).")
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
    EventsView()
}

