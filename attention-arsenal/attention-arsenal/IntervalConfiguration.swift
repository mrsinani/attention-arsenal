import Foundation

// MARK: - Interval Type Enum
enum IntervalType: Int16, CaseIterable, Identifiable {
    case none = 0
    case minutes = 1
    case hours = 2
    case daily = 3
    case weekly = 4
    case monthly = 5
    
    var id: Int16 { rawValue }
    
    var displayName: String {
        switch self {
        case .none: return "No notifications"
        case .minutes: return "Minutes"
        case .hours: return "Hours"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }
    
    var icon: String {
        switch self {
        case .none: return "bell.slash"
        case .minutes: return "clock"
        case .hours: return "clock.fill"
        case .daily: return "sun.max"
        case .weekly: return "calendar.badge.clock"
        case .monthly: return "calendar"
        }
    }
    
    /// Available values for this interval type
    var availableValues: [Int16] {
        switch self {
        case .none: return []
        case .minutes: return [5, 15, 30]
        case .hours: return [1, 2, 4, 6, 12]
        case .daily: return [1] // Every day (days selection handles which days)
        case .weekly: return [1] // Always every week
        case .monthly: return [1, 2, 3, 6, 12] // Every 1, 2, 3, 6, or 12 months
        }
    }
    
    /// Whether this interval type needs time selection
    var needsTimeSelection: Bool {
        switch self {
        case .none, .minutes, .hours: return false
        case .daily, .weekly, .monthly: return true
        }
    }
    
    /// Whether this interval type needs day-of-week selection
    var needsDayOfWeekSelection: Bool {
        switch self {
        case .daily, .weekly: return true
        default: return false
        }
    }
    
    /// Whether this interval type needs day-of-month selection
    var needsDayOfMonthSelection: Bool {
        self == .monthly
    }
}

// MARK: - Weekday Enum
enum Weekday: Int, CaseIterable, Identifiable {
    case sunday = 0
    case monday = 1
    case tuesday = 2
    case wednesday = 3
    case thursday = 4
    case friday = 5
    case saturday = 6
    
    var id: Int { rawValue }
    
    var shortName: String {
        switch self {
        case .sunday: return "S"
        case .monday: return "M"
        case .tuesday: return "T"
        case .wednesday: return "W"
        case .thursday: return "T"
        case .friday: return "F"
        case .saturday: return "S"
        }
    }
    
    var fullName: String {
        switch self {
        case .sunday: return "Sunday"
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        }
    }
    
    /// Bitmask value for this day
    var bitmask: Int16 {
        Int16(1 << rawValue)
    }
    
    /// Calendar weekday (1 = Sunday, 7 = Saturday)
    var calendarWeekday: Int {
        rawValue + 1
    }
}

// MARK: - Days Bitmask Helper
struct DaysBitmask {
    var value: Int16
    
    init(_ value: Int16 = 0) {
        self.value = value
    }
    
    /// Create bitmask for all weekdays (Mon-Fri)
    static var weekdays: DaysBitmask {
        var mask = DaysBitmask()
        mask.set(.monday, selected: true)
        mask.set(.tuesday, selected: true)
        mask.set(.wednesday, selected: true)
        mask.set(.thursday, selected: true)
        mask.set(.friday, selected: true)
        return mask
    }
    
    /// Create bitmask for all days
    static var allDays: DaysBitmask {
        DaysBitmask(0b1111111) // All 7 days
    }
    
    /// Create bitmask for today only
    static var today: DaysBitmask {
        let weekday = Calendar.current.component(.weekday, from: Date())
        // Calendar weekday is 1-7 (Sun-Sat), convert to our 0-6
        let dayIndex = weekday - 1
        var mask = DaysBitmask()
        if let day = Weekday(rawValue: dayIndex) {
            mask.set(day, selected: true)
        }
        return mask
    }
    
    func isSelected(_ day: Weekday) -> Bool {
        (value & day.bitmask) != 0
    }
    
    mutating func set(_ day: Weekday, selected: Bool) {
        if selected {
            value |= day.bitmask
        } else {
            value &= ~day.bitmask
        }
    }
    
    mutating func toggle(_ day: Weekday) {
        value ^= day.bitmask
    }
    
    /// Get array of selected weekdays
    var selectedDays: [Weekday] {
        Weekday.allCases.filter { isSelected($0) }
    }
    
    /// Get calendar weekday values (1-7) for selected days
    var calendarWeekdays: [Int] {
        selectedDays.map { $0.calendarWeekday }
    }
    
    /// Check if any day is selected
    var hasSelection: Bool {
        value != 0
    }
    
    /// Human-readable description of selected days
    var description: String {
        let selected = selectedDays
        
        if selected.isEmpty {
            return "No days selected"
        }
        
        // Check for common patterns
        if value == DaysBitmask.allDays.value {
            return "Every day"
        }
        
        if value == DaysBitmask.weekdays.value {
            return "Weekdays"
        }
        
        // Check for weekend only
        let weekendMask = Weekday.saturday.bitmask | Weekday.sunday.bitmask
        if value == weekendMask {
            return "Weekends"
        }
        
        // List individual days
        if selected.count <= 3 {
            return selected.map { $0.fullName }.joined(separator: ", ")
        } else {
            return selected.map { $0.shortName }.joined(separator: ", ")
        }
    }
}

// MARK: - Month Days Bitmask Helper
struct MonthDaysBitmask {
    var value: Int32  // Use Int32 to support all 31 days (bits 1-31)
    
    init(_ value: Int32 = 0) {
        self.value = value
    }
    
    /// Create bitmask for a single day (1-31)
    static func day(_ day: Int) -> MonthDaysBitmask {
        guard day >= 1 && day <= 31 else { return MonthDaysBitmask() }
        return MonthDaysBitmask(1 << (day - 1))
    }
    
    /// Create bitmask for today's day of month
    static var today: MonthDaysBitmask {
        let day = Calendar.current.component(.day, from: Date())
        return MonthDaysBitmask.day(day)
    }
    
    func isSelected(_ day: Int) -> Bool {
        guard day >= 1 && day <= 31 else { return false }
        return (value & Int32(1 << (day - 1))) != 0
    }
    
    mutating func set(_ day: Int, selected: Bool) {
        guard day >= 1 && day <= 31 else { return }
        let bit = Int32(1 << (day - 1))
        if selected {
            value |= bit
        } else {
            value &= ~bit
        }
    }
    
    mutating func toggle(_ day: Int) {
        guard day >= 1 && day <= 31 else { return }
        value ^= Int32(1 << (day - 1))
    }
    
    /// Get array of selected days (1-31)
    var selectedDays: [Int] {
        (1...31).filter { isSelected($0) }
    }
    
    /// Check if any day is selected
    var hasSelection: Bool {
        value != 0
    }
    
    /// Human-readable description of selected days
    var description: String {
        let selected = selectedDays
        
        if selected.isEmpty {
            return "No days selected"
        }
        
        if selected.count == 1 {
            return ordinalDay(Int16(selected[0]))
        }
        
        if selected.count <= 5 {
            return selected.map { ordinalDay(Int16($0)) }.joined(separator: ", ")
        }
        
        return "\(selected.count) days"
    }
    
    private func ordinalDay(_ day: Int16) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: day)) ?? "\(day)"
    }
}

// MARK: - Interval Configuration
struct IntervalConfiguration {
    var type: IntervalType
    var value: Int16
    var hour: Int16
    var minute: Int16
    var days: DaysBitmask
    var monthDays: MonthDaysBitmask
    
    /// Create configuration with smart defaults
    init(
        type: IntervalType = .none,
        value: Int16 = 1,
        hour: Int16 = 9,
        minute: Int16 = 0,
        days: DaysBitmask = .weekdays,
        monthDays: MonthDaysBitmask = .today
    ) {
        self.type = type
        self.value = value
        self.hour = hour
        self.minute = minute
        self.days = days
        self.monthDays = monthDays
    }
    
    /// Create from Arsenal entity
    init(from arsenal: Arsenal) {
        self.type = IntervalType(rawValue: arsenal.intervalType) ?? .none
        self.value = arsenal.intervalValue
        self.hour = arsenal.notificationHour
        self.minute = arsenal.notificationMinute
        self.days = DaysBitmask(arsenal.notificationDays)
        // Convert old single dayOfMonth to bitmask, or use notificationInterval as bitmask if available
        // For backward compatibility, if dayOfMonth is set, use it; otherwise check notificationInterval
        if arsenal.notificationDayOfMonth > 0 && arsenal.notificationDayOfMonth <= 31 {
            self.monthDays = MonthDaysBitmask.day(Int(arsenal.notificationDayOfMonth))
        } else {
            // Try to interpret notificationInterval as bitmask (for new data)
            self.monthDays = MonthDaysBitmask(Int32(arsenal.notificationInterval))
        }
    }
    
    /// Apply configuration to Arsenal entity
    func apply(to arsenal: Arsenal) {
        arsenal.intervalType = type.rawValue
        arsenal.intervalValue = value
        arsenal.notificationHour = hour
        arsenal.notificationMinute = minute
        arsenal.notificationDays = days.value
        // Store month days bitmask in notificationInterval (Int32) for monthly intervals
        // For backward compatibility, also set dayOfMonth to first selected day
        if type == .monthly {
            arsenal.notificationInterval = monthDays.value
            if let firstDay = monthDays.selectedDays.first {
                arsenal.notificationDayOfMonth = Int16(firstDay)
            } else {
                arsenal.notificationDayOfMonth = 1
            }
        } else {
            arsenal.notificationInterval = 0
            arsenal.notificationDayOfMonth = 1
        }
    }
    
    /// Time interval in seconds for minutes/hours intervals
    var timeIntervalInSeconds: TimeInterval? {
        switch type {
        case .minutes:
            return TimeInterval(value) * 60
        case .hours:
            return TimeInterval(value) * 3600
        default:
            return nil
        }
    }
    
    /// Human-readable summary of the interval
    var summary: String {
        switch type {
        case .none:
            return "No notifications"
            
        case .minutes:
            return "Every \(value) minute\(value == 1 ? "" : "s")"
            
        case .hours:
            return "Every \(value) hour\(value == 1 ? "" : "s")"
            
        case .daily:
            let timeStr = formatTime(hour: hour, minute: minute)
            if days.value == DaysBitmask.allDays.value {
                return "Daily at \(timeStr)"
            } else {
                return "\(days.description) at \(timeStr)"
            }
            
        case .weekly:
            let timeStr = formatTime(hour: hour, minute: minute)
            return "Every week on \(days.description) at \(timeStr)"
            
        case .monthly:
            let timeStr = formatTime(hour: hour, minute: minute)
            let monthStr = value == 1 ? "month" : "\(value) months"
            let dayStr = monthDays.description
            return "Every \(monthStr) on \(dayStr) at \(timeStr)"
        }
    }
    
    private func formatTime(hour: Int16, minute: Int16) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        
        var components = DateComponents()
        components.hour = Int(hour)
        components.minute = Int(minute)
        
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        return "\(hour):\(String(format: "%02d", minute))"
    }
    
    private func ordinalDay(_ day: Int16) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: day)) ?? "\(day)"
    }
}

// MARK: - Default Configurations
extension IntervalConfiguration {
    /// Smart default for daily notifications
    static var defaultDaily: IntervalConfiguration {
        IntervalConfiguration(
            type: .daily,
            value: 1,
            hour: 9,
            minute: 0,
            days: .allDays,
            monthDays: MonthDaysBitmask()
        )
    }
    
    /// Smart default for weekly notifications (current day)
    static var defaultWeekly: IntervalConfiguration {
        IntervalConfiguration(
            type: .weekly,
            value: 1,
            hour: 9,
            minute: 0,
            days: .today,
            monthDays: MonthDaysBitmask()
        )
    }
    
    /// Smart default for monthly notifications
    static var defaultMonthly: IntervalConfiguration {
        return IntervalConfiguration(
            type: .monthly,
            value: 1,
            hour: 9,
            minute: 0,
            days: .weekdays,
            monthDays: .today
        )
    }
    
    /// Create default configuration for a given type
    static func defaultFor(type: IntervalType) -> IntervalConfiguration {
        switch type {
        case .none:
            return IntervalConfiguration(type: .none)
        case .minutes:
            return IntervalConfiguration(type: .minutes, value: 15)
        case .hours:
            return IntervalConfiguration(type: .hours, value: 1)
        case .daily:
            return defaultDaily
        case .weekly:
            return defaultWeekly
        case .monthly:
            return defaultMonthly
        }
    }
}
