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

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "AttentionArsenal")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        } else {
            // Use App Groups container for shared data access with widget
            if let sharedStoreURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.attentionarsenal.shared") {
                let storeURL = sharedStoreURL.appendingPathComponent("AttentionArsenal.sqlite")
                let description = NSPersistentStoreDescription(url: storeURL)
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