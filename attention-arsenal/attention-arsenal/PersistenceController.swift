import CoreData

struct PersistenceController {
    static let shared = PersistenceController()
    
    // Flag to track if migration has been attempted
    private static let migrationKey = "HasMigratedToAppGroups"

    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        
        // Create sample data for previews
        let sampleArsenal = Arsenal(context: viewContext)
        sampleArsenal.title = "Sample Arsenal"
        sampleArsenal.arsenalDescription = "This is a sample arsenal for preview purposes"
        sampleArsenal.createdDate = Date()
        sampleArsenal.startDate = Date()
        sampleArsenal.endDate = Date().addingTimeInterval(3600)
        sampleArsenal.isCompleted = false
        sampleArsenal.notificationInterval = 30 // 30 minutes
        
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentContainer

    /// Loaded once and shared by every container. `NSPersistentContainer(name:)` loads its own
    /// copy of the model, so a second controller (tests, previews) registers the Arsenal entity
    /// twice and Core Data can no longer map the class to a unique entity — `Arsenal(context:)`
    /// then silently drops the values you set on it.
    private static let managedObjectModel: NSManagedObjectModel = {
        guard let url = Bundle.main.url(forResource: "AttentionArsenal", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url) else {
            fatalError("Failed to load the AttentionArsenal Core Data model")
        }
        return model
    }()

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "AttentionArsenal", managedObjectModel: Self.managedObjectModel)
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        } else {
            // Use App Groups container for shared data access with widget
            if let sharedStoreURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.attentionarsenal.shared") {
                let storeURL = sharedStoreURL.appendingPathComponent("AttentionArsenal.sqlite")
                let description = NSPersistentStoreDescription(url: storeURL)
                // Stated explicitly (they are also the defaults) because this app ships model
                // changes — v1.8 added calendarEventID — and an existing store must migrate
                // rather than fail to load and take the user's arsenals with it.
                description.shouldMigrateStoreAutomatically = true
                description.shouldInferMappingModelAutomatically = true
                container.persistentStoreDescriptions = [description]
            }
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
        
        // Perform one-time migration if needed
        if !inMemory {
            migrateDataToAppGroupsIfNeeded()
        }
    }
    
    // MARK: - Data Migration
    private func migrateDataToAppGroupsIfNeeded() {
        // Check if migration has already been done
        guard !UserDefaults.standard.bool(forKey: Self.migrationKey) else {
            return
        }
        
        // Get the old store location (default app container)
        guard let oldStoreURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("AttentionArsenal.sqlite") else {
            return
        }
        
        // Check if old store exists
        guard FileManager.default.fileExists(atPath: oldStoreURL.path) else {
            // No old data to migrate, mark as complete
            UserDefaults.standard.set(true, forKey: Self.migrationKey)
            return
        }
        
        // Get the new store location (App Groups container)
        guard let sharedStoreURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.attentionarsenal.shared")?.appendingPathComponent("AttentionArsenal.sqlite") else {
            return
        }
        
        // If shared store already exists, assume migration is complete
        if FileManager.default.fileExists(atPath: sharedStoreURL.path) {
            UserDefaults.standard.set(true, forKey: Self.migrationKey)
            return
        }
        
        // Perform migration by copying the store files
        do {
            let fileManager = FileManager.default
            
            // Copy main store file
            try fileManager.copyItem(at: oldStoreURL, to: sharedStoreURL)
            
            // Copy WAL file if exists
            let oldWAL = oldStoreURL.deletingPathExtension().appendingPathExtension("sqlite-wal")
            let newWAL = sharedStoreURL.deletingPathExtension().appendingPathExtension("sqlite-wal")
            if fileManager.fileExists(atPath: oldWAL.path) {
                try? fileManager.copyItem(at: oldWAL, to: newWAL)
            }
            
            // Copy SHM file if exists
            let oldSHM = oldStoreURL.deletingPathExtension().appendingPathExtension("sqlite-shm")
            let newSHM = sharedStoreURL.deletingPathExtension().appendingPathExtension("sqlite-shm")
            if fileManager.fileExists(atPath: oldSHM.path) {
                try? fileManager.copyItem(at: oldSHM, to: newSHM)
            }
            
            // Mark migration as complete
            UserDefaults.standard.set(true, forKey: Self.migrationKey)
            
            print("✅ Successfully migrated data to App Groups container")
        } catch {
            print("⚠️ Failed to migrate data: \(error.localizedDescription)")
        }
    }
} 