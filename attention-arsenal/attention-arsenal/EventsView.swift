import SwiftUI
import EventKit

struct EventsView: View {
    @StateObject private var calendarManager = CalendarManager.shared
    @State private var selectedRange: EventTimeRange = .nextWeek
    @State private var showingPermissionAlert = false
    @State private var isLoading = false
    
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
                    EventsList(events: calendarManager.events)
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
    
    var body: some View {
        List {
            ForEach(groupedEvents, id: \.date) { group in
                Section(header: Text(group.title)) {
                    ForEach(group.events, id: \.eventIdentifier) { event in
                        EventRow(event: event)
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
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
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
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
        }
        .padding(.vertical, 4)
    }
    
    private func timeString(for event: EKEvent) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        
        let startTime = formatter.string(from: event.startDate)
        let endTime = formatter.string(from: event.endDate)
        
        return "\(startTime) - \(endTime)"
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

