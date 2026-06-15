import Foundation

/// Service for generating AI-powered reminders from emails
/// Reuses the same pattern as AIReminderService
class AIEmailReminderService {
    static let shared = AIEmailReminderService()
    
    private init() {}
    
    /// Generate a reminder suggestion based on an email
    /// - Parameter email: The email to create a reminder for
    /// - Returns: A ReminderSuggestion with title, description, and notification interval
    func generateReminder(for email: EmailMessage) async throws -> ReminderSuggestion {
        // Create a focused prompt for the AI
        let prompt = createPrompt(for: email)
        
        // Get OpenAI response
        let response = try await OpenAIService.shared.sendPrompt(prompt)
        
        // Parse the response (reusing the same parsing logic)
        return try parseResponse(response, for: email)
    }
    
    private func createPrompt(for email: EmailMessage) -> String {
        let subject = email.subject
        let sender = email.sender
        let body = String(email.body.prefix(300)) // Limit body length
        let receivedDate = formatDate(email.date)

        let today = Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, MMMM d, yyyy"
        let todayString = fmt.string(from: today)

        return """
        Today is \(todayString).
        Create a reminder for this email. Respond ONLY with valid JSON.

        Email From: \(sender)
        Subject: "\(subject)"
        Received: \(receivedDate)
        Body: \(body)

        Generate a SHORT reminder title (max 5 words), helpful description, and appropriate notification interval.
        If the email mentions a specific deadline or action date (e.g. "due by Friday", "meeting on March 30",
        "respond by tomorrow"), extract it as targetDate in "YYYY-MM-DD" format; otherwise null.

        Available intervals (in minutes): 5, 15, 30, 60, 120, 240, 360, 720, 1440

        Choose interval based on email urgency:
        - Urgent/Time-sensitive: 30-60 minutes
        - Follow-up needed: 120-240 minutes
        - General tasks: 360-720 minutes
        - Low priority: 1440 minutes (daily)

        Respond with this exact JSON format:
        {
          "title": "short reminder title here",
          "description": "helpful action items or context from the email",
          "notificationInterval": 120,
          "targetDate": null
        }
        """
    }
    
    private func parseResponse(_ response: String, for email: EmailMessage) throws -> ReminderSuggestion {
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
            // Use a richer response type to capture the optional targetDate from AI.
            let raw = try JSONDecoder().decode(EmailReminderResponse.self, from: jsonData)

            // Validate the interval is one of our supported values
            let validIntervals: [Int32] = [5, 15, 30, 60, 120, 240, 360, 720, 1440]
            let interval = validIntervals.contains(raw.notificationInterval) ? raw.notificationInterval : 120

            var suggestion = ReminderSuggestion(
                title: raw.title,
                description: raw.description,
                notificationInterval: interval
            )

            // If the AI returned a deadline date, schedule a one-time reminder at 9 am on that day.
            if let dateStr = raw.targetDate {
                let dateFmt = DateFormatter()
                dateFmt.dateFormat = "yyyy-MM-dd"
                dateFmt.locale = Locale(identifier: "en_US_POSIX")
                if let deadline = dateFmt.date(from: dateStr) {
                    // Fire at 09:00 on the deadline date (or earlier if interval pushes it sooner)
                    let calendar = Calendar.current
                    if let fireDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: deadline),
                       fireDate > Date() {
                        suggestion.targetDatetime = fireDate
                    }
                }
            }

            return suggestion
        } catch {
            // Fallback to a sensible default
            return createFallbackSuggestion(for: email)
        }
    }

    // MARK: - Private Response Type

    private struct EmailReminderResponse: Codable {
        let title: String
        let description: String
        let notificationInterval: Int32
        let targetDate: String?
    }
    
    private func createFallbackSuggestion(for email: EmailMessage) -> ReminderSuggestion {
        let title = "Reply: \(email.sender)"
        let description = "Follow up on: \(email.subject)"
        let interval: Int32 = 240 // 4 hours
        
        return ReminderSuggestion(
            title: String(title.prefix(50)),
            description: String(description.prefix(200)),
            notificationInterval: interval
        )
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

