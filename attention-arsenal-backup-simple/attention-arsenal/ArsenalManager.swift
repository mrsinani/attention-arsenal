import CoreData
import Foundation
import UserNotifications

// MARK: - Notification Interval Enum
enum NotificationInterval: Int16, CaseIterable {
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
        }
    }
    
    var timeInterval: TimeInterval {
        return TimeInterval(self.rawValue * 60) // Convert minutes to seconds
    }
}

class ArsenalManager: ObservableObject {
    private let viewContext: NSManagedObjectContext
    private let notificationManager = NotificationManager.shared
    
    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.viewContext = context
    }
    
    // MARK: - Create
    func createArsenal(title: String, description: String? = nil, dueDate: Date? = nil, notificationInterval: Int16 = 0) -> Arsenal? {
        let arsenal = Arsenal(context: viewContext)
        arsenal.title = title
        arsenal.arsenalDescription = description
        arsenal.dueDate = dueDate
        arsenal.notificationInterval = notificationInterval
        arsenal.createdDate = Date()
        arsenal.isCompleted = false
        
        let success = saveContext()
        if success && notificationInterval > 0 {
            notificationManager.scheduleNotification(for: arsenal)
        }
        
        return success ? arsenal : nil
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
    func updateArsenal(_ arsenal: Arsenal, title: String? = nil, description: String? = nil, dueDate: Date? = nil, notificationInterval: Int16? = nil, isCompleted: Bool? = nil) -> Bool {
        if let title = title {
            arsenal.title = title
        }
        if let description = description {
            arsenal.arsenalDescription = description
        }
        if let dueDate = dueDate {
            arsenal.dueDate = dueDate
        }
        if let notificationInterval = notificationInterval {
            arsenal.notificationInterval = notificationInterval
        }
        if let isCompleted = isCompleted {
            arsenal.isCompleted = isCompleted
        }
        
        return saveContext()
    }
    
    func toggleCompletion(for arsenal: Arsenal) -> Bool {
        arsenal.isCompleted.toggle()
        let success = saveContext()
        
        if success {
            if arsenal.isCompleted {
                // Cancel notifications when arsenal is completed
                notificationManager.cancelNotifications(for: arsenal)
            } else {
                // Re-schedule notifications if arsenal is uncompleted and has interval
                if arsenal.notificationInterval > 0 {
                    notificationManager.scheduleNotification(for: arsenal)
                }
            }
        }
        
        return success
    }
    
    // MARK: - Delete
    func deleteArsenal(_ arsenal: Arsenal) -> Bool {
        // Cancel notifications before deleting
        notificationManager.cancelNotifications(for: arsenal)
        viewContext.delete(arsenal)
        return saveContext()
    }
    
    func deleteAllArsenals() -> Bool {
        let request: NSFetchRequest<NSFetchRequestResult> = Arsenal.fetchRequest()
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        
        do {
            try viewContext.execute(deleteRequest)
            return saveContext()
        } catch {
            print("Error deleting all arsenals: \(error)")
            return false
        }
    }
    
    // MARK: - Helper Methods
    private func saveContext() -> Bool {
        do {
            try viewContext.save()
            return true
        } catch {
            print("Error saving context: \(error)")
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