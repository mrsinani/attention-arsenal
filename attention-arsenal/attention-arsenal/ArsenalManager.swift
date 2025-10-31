import CoreData
import Foundation
import UserNotifications
import WidgetKit

// MARK: - Notification Interval Enum
enum NotificationInterval: Int32, CaseIterable {
    case none = 0
    case fiveMinutes = 5
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60
    case twoHours = 120
    case fourHours = 240
    case sixHours = 360
    case twelveHours = 720
    case daily = 1440
    case weekly = 10080        // 7 days
    case biweekly = 20160      // 14 days
    case monthly = 43200       // 30 days
    case custom = -1           // Special case for custom intervals
    
    var displayName: String {
        switch self {
        case .none:
            return "No notifications"
        case .fiveMinutes:
            return "Every 5 minutes"
        case .fifteenMinutes:
            return "Every 15 minutes"
        case .thirtyMinutes:
            return "Every 30 minutes"
        case .oneHour:
            return "Every hour"
        case .twoHours:
            return "Every 2 hours"
        case .fourHours:
            return "Every 4 hours"
        case .sixHours:
            return "Every 6 hours"
        case .twelveHours:
            return "Every 12 hours"
        case .daily:
            return "Daily"
        case .weekly:
            return "Weekly"
        case .biweekly:
            return "Every 2 weeks"
        case .monthly:
            return "Monthly"
        case .custom:
            return "Custom"
        }
    }
    
    var timeInterval: TimeInterval {
        return TimeInterval(self.rawValue * 60) // Convert minutes to seconds
    }
}

// MARK: - Custom Duration
enum DurationUnit: String, CaseIterable, Identifiable {
    case minutes = "Minutes"
    case hours = "Hours"
    case days = "Days"
    case weeks = "Weeks"
    case months = "Months"
    
    var id: String { rawValue }
    
    var minutesMultiplier: Int32 {
        switch self {
        case .minutes: return 1
        case .hours: return 60
        case .days: return 1440        // 24 hours
        case .weeks: return 10080      // 7 days
        case .months: return 43200     // 30 days (approximate)
        }
    }
    
    var maxValue: Int32 {
        // Conservative limits to prevent overflow when multiplying
        // Int32 max is 2,147,483,647, so we stay well below that
        switch self {
        case .minutes:
            return 10_000 // ~7 days max
        case .hours:
            return 1_000  // ~41 days max
        case .days:
            return 365    // 1 year max
        case .weeks:
            return 52     // 1 year max
        case .months:
            return 24     // 2 years max
        }
    }
}

struct CustomDuration {
    var value: Int32
    var unit: DurationUnit
    
    var totalMinutes: Int32 {
        return value * unit.minutesMultiplier
    }
    
    static func fromMinutes(_ minutes: Int32) -> CustomDuration? {
        guard minutes > 0 else { return nil }
        
        // Try to find the best unit representation
        if minutes % DurationUnit.months.minutesMultiplier == 0 {
            return CustomDuration(value: minutes / DurationUnit.months.minutesMultiplier, unit: .months)
        } else if minutes % DurationUnit.weeks.minutesMultiplier == 0 {
            return CustomDuration(value: minutes / DurationUnit.weeks.minutesMultiplier, unit: .weeks)
        } else if minutes % DurationUnit.days.minutesMultiplier == 0 {
            return CustomDuration(value: minutes / DurationUnit.days.minutesMultiplier, unit: .days)
        } else if minutes % DurationUnit.hours.minutesMultiplier == 0 {
            return CustomDuration(value: minutes / DurationUnit.hours.minutesMultiplier, unit: .hours)
        } else {
            return CustomDuration(value: minutes, unit: .minutes)
        }
    }
}

class ArsenalManager: ObservableObject {
    private let viewContext: NSManagedObjectContext
    private let notificationManager = NotificationManager.shared
    
    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.viewContext = context
    }
    
    // MARK: - Create
    func createArsenal(title: String, description: String? = nil, startDate: Date? = nil, endDate: Date? = nil, notificationInterval: Int32 = 0) -> Arsenal? {
        let arsenal = Arsenal(context: viewContext)
        arsenal.title = title
        arsenal.arsenalDescription = description
        arsenal.startDate = startDate
        arsenal.endDate = endDate
        arsenal.notificationInterval = notificationInterval
        arsenal.createdDate = Date()
        arsenal.isCompleted = false
        
        do {
            try viewContext.save()
            
            // Schedule notification if needed
            if notificationInterval > 0 {
                notificationManager.scheduleNotification(for: arsenal)
            }
            
            // Reload widget to show new arsenal
            WidgetCenter.shared.reloadAllTimelines()
            
            return arsenal
        } catch {
            print("Error saving context: \(error)")
            return nil
        }
    }
    
    // MARK: - Read
    func fetchArsenals(completed: Bool? = nil) -> [Arsenal] {
        let request: NSFetchRequest<Arsenal> = Arsenal.fetchRequest()
        
        if let completed = completed {
            request.predicate = NSPredicate(format: "isCompleted == %@", NSNumber(value: completed))
        }
        
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Arsenal.createdDate, ascending: false)
        ]
        
        do {
            return try viewContext.fetch(request)
        } catch {
            print("Error fetching arsenals: \(error)")
            return []
        }
    }
    
    func fetchArsenal(by id: NSManagedObjectID) -> Arsenal? {
        do {
            return try viewContext.existingObject(with: id) as? Arsenal
        } catch {
            print("Error fetching arsenal by ID: \(error)")
            return nil
        }
    }
    
    // MARK: - Update
    func updateArsenal(_ arsenal: Arsenal, title: String? = nil, description: String? = nil, startDate: Date? = nil, endDate: Date? = nil, notificationInterval: Int32? = nil, isCompleted: Bool? = nil) -> Bool {
        if let title = title {
            arsenal.title = title
        }
        if let description = description {
            arsenal.arsenalDescription = description
        }
        if let startDate = startDate {
            arsenal.startDate = startDate
        }
        if let endDate = endDate {
            arsenal.endDate = endDate
        }
        if let notificationInterval = notificationInterval {
            arsenal.notificationInterval = notificationInterval
        }
        if let isCompleted = isCompleted {
            arsenal.isCompleted = isCompleted
        }
        
        // Use the same context as the arsenal object
        let context = arsenal.managedObjectContext ?? viewContext
        
        do {
            try context.save()
            
            // Reload widget to reflect changes
            WidgetCenter.shared.reloadAllTimelines()
            
            return true
        } catch {
            print("Error saving context: \(error)")
            return false
        }
    }
    
    func toggleCompletion(for arsenal: Arsenal) -> Bool {
        arsenal.isCompleted.toggle()
        
        do {
            try viewContext.save()
            
            // Handle notifications
            if arsenal.isCompleted {
                notificationManager.cancelNotifications(for: arsenal)
            } else if arsenal.notificationInterval > 0 {
                notificationManager.scheduleNotification(for: arsenal)
            }
            
            // Reload widget to update completion status
            WidgetCenter.shared.reloadAllTimelines()
            
            return true
        } catch {
            print("Error saving context: \(error)")
            return false
        }
    }
    
    // MARK: - Delete
    func deleteArsenal(_ arsenal: Arsenal) -> Bool {
        // Cancel notifications before deleting
        notificationManager.cancelNotifications(for: arsenal)
        viewContext.delete(arsenal)
        
        do {
            try viewContext.save()
            
            // Reload widget to remove deleted arsenal
            WidgetCenter.shared.reloadAllTimelines()
            
            return true
        } catch {
            print("Error saving context: \(error)")
            return false
        }
    }
    
    func deleteAllArsenals() -> Bool {
        let request: NSFetchRequest<NSFetchRequestResult> = Arsenal.fetchRequest()
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        
        do {
            try viewContext.execute(deleteRequest)
            try viewContext.save()
            
            // Reload widget to clear all arsenals
            WidgetCenter.shared.reloadAllTimelines()
            
            return true
        } catch {
            print("Error deleting all arsenals: \(error)")
            return false
        }
    }
    
    // MARK: - Statistics
    func getArsenalStats() -> (total: Int, completed: Int, pending: Int) {
        let allArsenals = fetchArsenals()
        let completed = allArsenals.filter { $0.isCompleted }.count
        let pending = allArsenals.filter { !$0.isCompleted }.count
        
        return (total: allArsenals.count, completed: completed, pending: pending)
    }
}