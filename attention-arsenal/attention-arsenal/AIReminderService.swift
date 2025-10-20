import Foundation
import EventKit

/// Service for generating AI-powered reminders from calendar events
class AIReminderService {
    static let shared = AIReminderService()
    
    private init() {}
    
    /// Generate a reminder suggestion based on a calendar event
    /// - Parameter event: The calendar event to create a reminder for
    /// - Returns: A ReminderSuggestion with title, description, and notification interval
    func generateReminder(for event: EKEvent) async throws -> ReminderSuggestion {
        // Create a focused prompt for the AI
        let prompt = createPrompt(for: event)
        
        // Get OpenAI response
        let response = try await OpenAIService.shared.sendPrompt(prompt)
        
        // Parse the response
        return try parseResponse(response, for: event)
    }
    
    private func createPrompt(for event: EKEvent) -> String {
        let eventTitle = event.title ?? "Untitled Event"
        let eventDate = formatDate(event.startDate)
        let timeUntilEvent = formatTimeUntil(event.startDate)
        let location = event.location ?? "No location"
        
        return """
        Create a reminder for this calendar event. Respond ONLY with valid JSON.
        
        Event: "\(eventTitle)"
        Date/Time: \(eventDate)
        Time until event: \(timeUntilEvent)
        Location: \(location)
        
        Generate a SHORT reminder title (max 5 words), helpful description, and appropriate notification interval.
        
        Available intervals (in minutes): 5, 15, 30, 60, 120, 240, 360, 720, 1440
        
        Choose interval based on:
        - Very important events (meetings, appointments): 60-120 minutes before
        - Casual events: 240-360 minutes before
        - All-day events or far future: 720-1440 minutes before
        
        Respond with this exact JSON format:
        {
          "title": "short reminder title here",
          "description": "helpful preparation tips or context",
          "notificationInterval": 60
        }
        """
    }
    
    private func parseResponse(_ response: String, for event: EKEvent) throws -> ReminderSuggestion {
        // Clean the response - remove markdown code blocks if present
        var cleanedResponse = response
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove markdown code blocks
        if cleanedResponse.hasPrefix("```json") {
            cleanedResponse = cleanedResponse
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else if cleanedResponse.hasPrefix("```") {
            cleanedResponse = cleanedResponse
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        guard let jsonData = cleanedResponse.data(using: .utf8) else {
            throw AIReminderError.invalidResponse
        }
        
        do {
            let suggestion = try JSONDecoder().decode(ReminderSuggestion.self, from: jsonData)
            
            // Validate the interval is one of our supported values
            let validIntervals: [Int32] = [5, 15, 30, 60, 120, 240, 360, 720, 1440]
            guard validIntervals.contains(suggestion.notificationInterval) else {
                // Default to 1 hour if invalid
                return ReminderSuggestion(
                    title: suggestion.title,
                    description: suggestion.description,
                    notificationInterval: 60
                )
            }
            
            return suggestion
        } catch {
            // Fallback to a sensible default
            return createFallbackSuggestion(for: event)
        }
    }
    
    private func createFallbackSuggestion(for event: EKEvent) -> ReminderSuggestion {
        let title = "Prepare for \(event.title ?? "Event")"
        let description = "Get ready for your upcoming event"
        let interval: Int32 = 60 // 1 hour before
        
        return ReminderSuggestion(
            title: String(title.prefix(50)), // Limit length
            description: description,
            notificationInterval: interval
        )
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatTimeUntil(_ date: Date) -> String {
        let now = Date()
        let timeInterval = date.timeIntervalSince(now)
        
        if timeInterval < 0 {
            return "Event has passed"
        }
        
        let hours = Int(timeInterval / 3600)
        let days = hours / 24
        
        if days > 1 {
            return "\(days) days away"
        } else if hours > 1 {
            return "\(hours) hours away"
        } else {
            let minutes = Int(timeInterval / 60)
            return "\(minutes) minutes away"
        }
    }
}

// MARK: - Models

struct ReminderSuggestion: Codable {
    let title: String
    let description: String
    let notificationInterval: Int32
}

enum AIReminderError: LocalizedError {
    case invalidResponse
    case parsingFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Failed to parse AI response"
        case .parsingFailed:
            return "Could not create reminder from response"
        }
    }
}

