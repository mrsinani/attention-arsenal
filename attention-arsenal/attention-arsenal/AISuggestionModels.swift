import Foundation
import SwiftUI

// MARK: - AI Suggestion Models
struct AISuggestion: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let description: String?
    let suggestedBy: SuggestionSource
    let priority: SuggestionPriority
    let estimatedDuration: TimeInterval?
    let suggestedNotificationInterval: NotificationInterval
    let createdAt: Date
    let context: String?
    
    init(title: String, description: String? = nil, suggestedBy: SuggestionSource, priority: SuggestionPriority = .medium, estimatedDuration: TimeInterval? = nil, suggestedNotificationInterval: NotificationInterval = .none, context: String? = nil) {
        self.title = title
        self.description = description
        self.suggestedBy = suggestedBy
        self.priority = priority
        self.estimatedDuration = estimatedDuration
        self.suggestedNotificationInterval = suggestedNotificationInterval
        self.createdAt = Date()
        self.context = context
    }
}

enum SuggestionSource: String, CaseIterable {
    case gmail = "Gmail"
    case calendar = "Calendar"
    case slack = "Slack"
    case notes = "Notes"
    case ai = "AI Assistant"
    case patterns = "Usage Patterns"
    
    var icon: String {
        switch self {
        case .gmail:
            return "envelope.fill"
        case .calendar:
            return "calendar"
        case .slack:
            return "message.fill"
        case .notes:
            return "note.text"
        case .ai:
            return "brain.head.profile"
        case .patterns:
            return "chart.line.uptrend.xyaxis"
        }
    }
    
    var color: Color {
        switch self {
        case .gmail:
            return .red
        case .calendar:
            return .blue
        case .slack:
            return .purple
        case .notes:
            return .orange
        case .ai:
            return .green
        case .patterns:
            return .indigo
        }
    }
}

enum SuggestionPriority: String, CaseIterable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case urgent = "Urgent"
    
    var color: Color {
        switch self {
        case .low:
            return .gray
        case .medium:
            return .blue
        case .high:
            return .orange
        case .urgent:
            return .red
        }
    }
}

// MARK: - AI Suggestion Manager
class AISuggestionManager: ObservableObject {
    @Published var suggestions: [AISuggestion] = []
    @Published var isLoading = false
    
    init() {
        loadMockSuggestions()
    }
    
    func loadMockSuggestions() {
        suggestions = [
            AISuggestion(
                title: "Review Q4 budget proposal",
                description: "Sarah mentioned this needs to be completed by Friday in your last email thread",
                suggestedBy: .gmail,
                priority: .high,
                estimatedDuration: 3600, // 1 hour
                suggestedNotificationInterval: .daily,
                context: "Email from Sarah Chen about Q4 planning"
            ),
            AISuggestion(
                title: "Prepare presentation slides",
                description: "Team meeting scheduled for tomorrow at 2 PM",
                suggestedBy: .calendar,
                priority: .urgent,
                estimatedDuration: 7200, // 2 hours
                suggestedNotificationInterval: .twoHours,
                context: "Calendar event: Team Quarterly Review"
            ),
            AISuggestion(
                title: "Call dentist for appointment",
                description: "You've been postponing this for 3 weeks based on your usage patterns",
                suggestedBy: .patterns,
                priority: .medium,
                estimatedDuration: 600, // 10 minutes
                suggestedNotificationInterval: .daily,
                context: "Recurring pattern: Health appointments"
            ),
            AISuggestion(
                title: "Update project documentation",
                description: "The team mentioned outdated docs in #dev-team channel",
                suggestedBy: .slack,
                priority: .medium,
                estimatedDuration: 1800, // 30 minutes
                suggestedNotificationInterval: .fourHours,
                context: "Slack discussion in #dev-team"
            ),
            AISuggestion(
                title: "Buy groceries for dinner party",
                description: "Weekend dinner party mentioned in your notes app",
                suggestedBy: .notes,
                priority: .low,
                estimatedDuration: 2400, // 40 minutes
                suggestedNotificationInterval: .daily,
                context: "Note: Weekend dinner party planning"
            )
        ]
    }
    
    func acceptSuggestion(_ suggestion: AISuggestion) {
        // Remove from suggestions
        suggestions.removeAll { $0.id == suggestion.id }
        
        // Create arsenal from suggestion
        let arsenalManager = ArsenalManager()
        _ = arsenalManager.createArsenal(
            title: suggestion.title,
            description: suggestion.description,
            dueDate: nil,
            notificationInterval: suggestion.suggestedNotificationInterval.rawValue
        )
    }
    
    func declineSuggestion(_ suggestion: AISuggestion) {
        suggestions.removeAll { $0.id == suggestion.id }
    }
    
    func refreshSuggestions() {
        isLoading = true
        
        // Simulate API call delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.loadMockSuggestions()
            self.isLoading = false
        }
    }
}
