import Foundation
import EventKit

/// Manager for accessing and displaying calendar events
class CalendarManager: ObservableObject {
    static let shared = CalendarManager()
    
    private let eventStore = EKEventStore()
    
    @Published var events: [EKEvent] = []
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    
    private init() {
        checkAuthorizationStatus()
    }
    
    /// Check current calendar authorization status
    func checkAuthorizationStatus() {
        if #available(iOS 17.0, *) {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        } else {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        }
    }
    
    /// Request calendar access permission
    func requestCalendarAccess() async -> Bool {
        do {
            if #available(iOS 17.0, *) {
                let granted = try await eventStore.requestFullAccessToEvents()
                await MainActor.run {
                    authorizationStatus = granted ? .fullAccess : .denied
                }
                return granted
            } else {
                let granted = try await eventStore.requestAccess(to: .event)
                await MainActor.run {
                    authorizationStatus = granted ? .authorized : .denied
                }
                return granted
            }
        } catch {
            print("Error requesting calendar access: \(error)")
            await MainActor.run {
                authorizationStatus = .denied
            }
            return false
        }
    }
    
    /// Fetch events for a given time range
    /// - Parameter range: The time range to fetch events for
    func fetchEvents(for range: EventTimeRange) async {
        // Check if we have permission
        guard isAuthorized else {
            print("Calendar access not authorized")
            return
        }
        
        let startDate = Date()
        let endDate = range.endDate(from: startDate)
        
        // Create predicate for events
        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: nil
        )
        
        // Fetch events
        let fetchedEvents = eventStore.events(matching: predicate)
        
        // Update on main thread
        await MainActor.run {
            self.events = fetchedEvents.sorted { $0.startDate < $1.startDate }
        }
    }
    
    /// Check if calendar access is authorized
    var isAuthorized: Bool {
        if #available(iOS 17.0, *) {
            return authorizationStatus == .fullAccess || authorizationStatus == .writeOnly
        } else {
            return authorizationStatus == .authorized
        }
    }
}

/// Time range options for displaying events
enum EventTimeRange: String, CaseIterable, Identifiable {
    case today = "Today"
    case tomorrow = "Tomorrow"
    case nextWeek = "Next 7 Days"
    case nextTwoWeeks = "Next 2 Weeks"
    case nextMonth = "Next Month"
    case nextThreeMonths = "Next 3 Months"
    
    var id: String { rawValue }
    
    /// Calculate end date from start date based on range
    func endDate(from startDate: Date) -> Date {
        let calendar = Calendar.current
        
        switch self {
        case .today:
            return calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate)
        case .tomorrow:
            return calendar.startOfDay(for: calendar.date(byAdding: .day, value: 2, to: startDate) ?? startDate)
        case .nextWeek:
            return calendar.date(byAdding: .day, value: 7, to: startDate) ?? startDate
        case .nextTwoWeeks:
            return calendar.date(byAdding: .day, value: 14, to: startDate) ?? startDate
        case .nextMonth:
            return calendar.date(byAdding: .month, value: 1, to: startDate) ?? startDate
        case .nextThreeMonths:
            return calendar.date(byAdding: .month, value: 3, to: startDate) ?? startDate
        }
    }
}

