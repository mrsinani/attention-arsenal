import CoreData
import Foundation
import UserNotifications
import WidgetKit

class ArsenalManager: ObservableObject {
    private let viewContext: NSManagedObjectContext
    private let notificationManager = NotificationManager.shared
    
    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.viewContext = context
    }
    
    // MARK: - Create
    func createArsenal(
        title: String,
        description: String? = nil,
        intervalConfig: IntervalConfiguration = IntervalConfiguration.defaultDaily
    ) -> Arsenal? {
        let arsenal = Arsenal(context: viewContext)
        arsenal.title = title
        arsenal.arsenalDescription = description
        arsenal.createdDate = Date()
        arsenal.isCompleted = false
        
        // Apply interval configuration
        intervalConfig.apply(to: arsenal)
        
        do {
            try viewContext.save()
            
            // Schedule notification if needed
            if intervalConfig.type != .none {
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
    func updateArsenal(
        _ arsenal: Arsenal,
        title: String? = nil,
        description: String? = nil,
        intervalConfig: IntervalConfiguration? = nil,
        isCompleted: Bool? = nil
    ) -> Bool {
        if let title = title {
            arsenal.title = title
        }
        if let description = description {
            arsenal.arsenalDescription = description
        }
        if let intervalConfig = intervalConfig {
            intervalConfig.apply(to: arsenal)
        }
        if let isCompleted = isCompleted {
            arsenal.isCompleted = isCompleted
        }
        
        // Use the same context as the arsenal object
        let context = arsenal.managedObjectContext ?? viewContext
        
        do {
            try context.save()
            
            // Update notifications
            notificationManager.updateNotification(for: arsenal)
            
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
            } else {
                let config = IntervalConfiguration(from: arsenal)
                if config.type != .none {
                    notificationManager.scheduleNotification(for: arsenal)
                }
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
    
    func deleteArsenals(_ arsenals: [Arsenal]) -> Bool {
        guard !arsenals.isEmpty else { return true }
        
        // Cancel notifications and delete each arsenal
        for arsenal in arsenals {
            notificationManager.cancelNotifications(for: arsenal)
            viewContext.delete(arsenal)
        }
        
        do {
            try viewContext.save()
            
            // Reload widget to remove deleted arsenals
            WidgetCenter.shared.reloadAllTimelines()
            
            return true
        } catch {
            print("Error deleting arsenals: \(error)")
            return false
        }
    }
    
    func deleteAllArsenals() -> Bool {
        let request: NSFetchRequest<NSFetchRequestResult> = Arsenal.fetchRequest()
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        
        do {
            try viewContext.execute(deleteRequest)
            try viewContext.save()
            
            // Cancel all notifications
            notificationManager.cancelAllNotifications()
            
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
