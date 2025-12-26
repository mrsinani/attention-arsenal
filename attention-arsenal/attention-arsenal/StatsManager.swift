import Foundation

/// Manages user statistics with iCloud sync via NSUbiquitousKeyValueStore
class StatsManager: ObservableObject {
    static let shared = StatsManager()
    
    private let store = NSUbiquitousKeyValueStore.default
    
    // Keys for iCloud storage
    private let totalCompletedKey = "totalCompleted"
    private let completionDatesKey = "completionDates" // Array of date strings
    
    // Local cache of completion dates (to avoid iCloud sync issues)
    private var cachedCompletionDates: [String] = []
    
    @Published var totalCompleted: Int = 0
    @Published var completedThisWeek: Int = 0
    @Published var longestStreak: Int = 0
    @Published var currentStreak: Int = 0
    
    private init() {
        // Listen for iCloud changes from other devices
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(iCloudDidUpdate),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store
        )
        
        // Sync with iCloud
        store.synchronize()
        
        // Load initial values
        loadStats()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func iCloudDidUpdate(_ notification: Notification) {
        DispatchQueue.main.async {
            self.loadStats()
        }
    }
    
    // MARK: - Public Methods
    
    /// Call this when an arsenal is completed
    func recordCompletion() {
        // Increment total
        totalCompleted += 1
        store.set(totalCompleted, forKey: totalCompletedKey)
        
        // Add today's date to completion dates (use cached copy)
        let today = dateString(from: Date())
        if !cachedCompletionDates.contains(today) {
            cachedCompletionDates.append(today)
        }
        store.set(cachedCompletionDates, forKey: completionDatesKey)
        
        // Sync
        store.synchronize()
        
        // Recalculate stats using cached dates
        calculateStats(from: cachedCompletionDates)
    }
    
    /// Call this when an arsenal completion is undone
    func undoCompletion() {
        // Decrement total (but don't go below 0)
        totalCompleted = max(0, totalCompleted - 1)
        store.set(totalCompleted, forKey: totalCompletedKey)
        store.synchronize()
        
        // Recalculate streak stats using cached dates (don't re-read from store)
        calculateStats(from: cachedCompletionDates)
    }
    
    /// Reset all stats (for debugging/testing)
    func resetStats() {
        store.set(0, forKey: totalCompletedKey)
        store.set([String](), forKey: completionDatesKey)
        store.synchronize()
        loadStats()
    }
    
    // MARK: - Private Methods
    
    private func loadStats() {
        totalCompleted = Int(store.longLong(forKey: totalCompletedKey))
        cachedCompletionDates = getCompletionDates()
        calculateStats(from: cachedCompletionDates)
    }
    
    private func getCompletionDates() -> [String] {
        return store.array(forKey: completionDatesKey) as? [String] ?? []
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

