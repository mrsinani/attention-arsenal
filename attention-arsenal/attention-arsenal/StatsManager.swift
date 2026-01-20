import Foundation

/// Manages user statistics with local storage (UserDefaults) as primary
/// and iCloud backup for device switches/reinstalls
class StatsManager: ObservableObject {
    static let shared = StatsManager()
    
    // Local storage (primary - always use this)
    private let defaults = UserDefaults.standard
    
    // iCloud storage (backup only)
    private let iCloudStore = NSUbiquitousKeyValueStore.default
    
    // Keys for storage
    private let totalCompletedKey = "stats_totalCompleted"
    private let completionDatesKey = "stats_completionDates"
    private let lastBackupKey = "stats_lastBackupDate"
    private let hasRestoredFromiCloudKey = "stats_hasRestoredFromiCloud"
    
    // Local cache of completion dates
    private var cachedCompletionDates: [String] = []
    
    @Published var totalCompleted: Int = 0
    @Published var completedThisWeek: Int = 0
    @Published var longestStreak: Int = 0
    @Published var currentStreak: Int = 0
    
    private init() {
        // First, check if we need to restore from iCloud (fresh install)
        restoreFromiCloudIfNeeded()
        
        // Load local stats
        loadLocalStats()
        
        // Backup to iCloud if needed (daily)
        backupToiCloudIfNeeded()
    }
    
    // MARK: - Public Methods
    
    /// Call this when an arsenal is completed
    func recordCompletion() {
        // Increment total
        totalCompleted += 1
        defaults.set(totalCompleted, forKey: totalCompletedKey)
        
        // Add today's date to completion dates
        let today = dateString(from: Date())
        if !cachedCompletionDates.contains(today) {
            cachedCompletionDates.append(today)
        }
        defaults.set(cachedCompletionDates, forKey: completionDatesKey)
        
        // Recalculate stats
        calculateStats(from: cachedCompletionDates)
        
        // Backup to iCloud (will check if daily backup needed)
        backupToiCloudIfNeeded()
    }
    
    /// Force backup to iCloud (call when app goes to background)
    func forceBackupToiCloud() {
        backupToiCloud()
    }
    
    // MARK: - Private Methods - Local Storage
    
    private func loadLocalStats() {
        totalCompleted = defaults.integer(forKey: totalCompletedKey)
        cachedCompletionDates = defaults.array(forKey: completionDatesKey) as? [String] ?? []
        calculateStats(from: cachedCompletionDates)
    }
    
    // MARK: - Private Methods - iCloud Backup
    
    private func restoreFromiCloudIfNeeded() {
        // Only restore if this is a fresh install (no local data and haven't restored before)
        let hasLocalData = defaults.integer(forKey: totalCompletedKey) > 0
        let hasRestoredBefore = defaults.bool(forKey: hasRestoredFromiCloudKey)
        
        if hasLocalData || hasRestoredBefore {
            return // Already have local data or already restored
        }
        
        // Try to sync iCloud first
        iCloudStore.synchronize()
        
        // Check if iCloud has backup data
        let iCloudTotal = Int(iCloudStore.longLong(forKey: totalCompletedKey))
        let iCloudDates = iCloudStore.array(forKey: completionDatesKey) as? [String] ?? []
        
        if iCloudTotal > 0 {
            // Restore from iCloud backup
            defaults.set(iCloudTotal, forKey: totalCompletedKey)
            defaults.set(iCloudDates, forKey: completionDatesKey)
            print("Stats restored from iCloud backup: \(iCloudTotal) completions")
        }
        
        // Mark that we've attempted restoration (don't try again)
        defaults.set(true, forKey: hasRestoredFromiCloudKey)
    }
    
    private func backupToiCloudIfNeeded() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Check when we last backed up
        if let lastBackup = defaults.object(forKey: lastBackupKey) as? Date {
            let lastBackupDay = calendar.startOfDay(for: lastBackup)
            if lastBackupDay >= today {
                return // Already backed up today
            }
        }
        
        // Perform backup
        backupToiCloud()
    }
    
    private func backupToiCloud() {
        iCloudStore.set(totalCompleted, forKey: totalCompletedKey)
        iCloudStore.set(cachedCompletionDates, forKey: completionDatesKey)
        iCloudStore.synchronize()
        
        // Record backup time
        defaults.set(Date(), forKey: lastBackupKey)
        print("Stats backed up to iCloud: \(totalCompleted) completions")
    }
    
    private func calculateStats(from dateStrings: [String]) {
        let calendar = Calendar.current
        let now = Date()
        
        // Convert strings to dates
        let dates = dateStrings.compactMap { date(from: $0) }.sorted()
        
        // Calculate completed this week
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
        completedThisWeek = dateStrings.filter { dateString in
            guard let date = date(from: dateString) else { return false }
            return date >= startOfWeek
        }.count
        
        // Calculate streaks
        guard !dates.isEmpty else {
            longestStreak = 0
            currentStreak = 0
            return
        }
        
        // Get unique days (normalized to start of day)
        let uniqueDays = Set(dates.map { calendar.startOfDay(for: $0) }).sorted()
        
        var longest = 1
        var current = 1
        var tempStreak = 1
        
        for i in 1..<uniqueDays.count {
            let previousDay = uniqueDays[i - 1]
            let currentDay = uniqueDays[i]
            
            // Check if consecutive days
            if let nextDay = calendar.date(byAdding: .day, value: 1, to: previousDay),
               calendar.isDate(nextDay, inSameDayAs: currentDay) {
                tempStreak += 1
                longest = max(longest, tempStreak)
            } else {
                tempStreak = 1
            }
        }
        
        longestStreak = longest
        
        // Calculate current streak (must include today or yesterday)
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        
        guard let lastCompletionDay = uniqueDays.last else {
            currentStreak = 0
            return
        }
        
        // Current streak only counts if we completed something today or yesterday
        if calendar.isDate(lastCompletionDay, inSameDayAs: today) ||
           calendar.isDate(lastCompletionDay, inSameDayAs: yesterday) {
            
            // Count backwards from most recent
            current = 1
            for i in stride(from: uniqueDays.count - 1, through: 1, by: -1) {
                let currentDay = uniqueDays[i]
                let previousDay = uniqueDays[i - 1]
                
                if let dayBefore = calendar.date(byAdding: .day, value: -1, to: currentDay),
                   calendar.isDate(dayBefore, inSameDayAs: previousDay) {
                    current += 1
                } else {
                    break
                }
            }
            currentStreak = current
        } else {
            currentStreak = 0
        }
    }
    
    // MARK: - Date Helpers
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    private func dateString(from date: Date) -> String {
        dateFormatter.string(from: date)
    }
    
    private func date(from string: String) -> Date? {
        dateFormatter.date(from: string)
    }
}

