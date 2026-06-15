import Foundation

/// Service for parsing natural language voice commands into arsenal data
class SiriArsenalParser {
    static let shared = SiriArsenalParser()
    
    private init() {}
    
    /// Parse voice input and extract arsenal details
    /// - Parameter voiceInput: The natural language text from Siri
    /// - Returns: Parsed arsenal data ready to create
    func parseVoiceInput(_ voiceInput: String) async throws -> ParsedArsenal {
        let prompt = createPrompt(for: voiceInput)
        
        // Get OpenAI response
        let response = try await OpenAIService.shared.sendPrompt(prompt)
        
        // Parse the response
        return try parseResponse(response, originalInput: voiceInput)
    }
    
    private func createPrompt(for input: String) -> String {
        let today = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        let todayString = formatter.string(from: today)

        return """
        Today is \(todayString).

        Parse this voice command into a reminder/task. Respond ONLY with valid JSON.

        User said: "\(input)"

        Extract the following:
        - A short title (max 5 words)
        - A helpful description
        - An end date ONLY if a specific deadline/event date is mentioned (null otherwise)
        - A targetDatetime ONLY if the user names a specific day+time to be reminded (e.g. "Wednesday at 8am", "tomorrow at 3pm", "Friday morning"); null for recurring or vague requests
        - Appropriate notification interval in minutes (used when targetDatetime is null)

        END DATE rules (endDate field, "YYYY-MM-DD"):
        - "tomorrow" = tomorrow's date
        - "next Friday", "this weekend" = calculate specific date
        - "in 3 days", "in 2 weeks" = calculate from today
        - "January 15", "Dec 25th" = specific date this year or next if passed
        - "Halloween" = October 31 / "Christmas" = December 25
        - NO specific deadline date mentioned = null

        TARGET DATETIME rules (targetDatetime field, "YYYY-MM-DDTHH:mm:ss"):
        - Use ONLY when the user explicitly names a specific day and/or time to be reminded
        - "Wednesday at 8am" → next Wednesday at 08:00:00
        - "tomorrow at 3pm" → tomorrow at 15:00:00
        - "Friday morning" → next Friday at 09:00:00
        - "every day at 9am", "every week", or no explicit time → null (use notificationInterval instead)
        - If only a day is given with no time, default to 09:00:00

        Notification intervals (in minutes) — used only when targetDatetime is null:
        5, 15, 30, 60, 120, 240, 360, 720, 1440 (daily), 10080 (weekly), 20160 (biweekly), 43200 (monthly)
        - Urgent/Soon: 30-60 | This week: 120-240 | Near future: 360-1440
        - Regular/far-future: 10080 (weekly) | Very long-term: 20160 or 43200

        Respond with this EXACT JSON format:
        {
          "title": "short title here",
          "description": "helpful description",
          "endDate": "2025-01-25" or null,
          "notificationInterval": 240,
          "targetDatetime": "2025-01-22T08:00:00" or null
        }

        DO NOT ask questions. DO NOT add explanations. ONLY return the JSON.
        """
    }
    
    private func parseResponse(_ response: String, originalInput: String) throws -> ParsedArsenal {
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
            throw SiriParserError.invalidResponse
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)

                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"

                if let date = formatter.date(from: dateString) {
                    return date
                }

                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Date string does not match expected format"
                )
            }

            let parsed = try decoder.decode(ParsedArsenalResponse.self, from: jsonData)

            // Resolve explicit targetDatetime to a one-time IntervalConfiguration when present.
            var targetDate: Date? = nil
            if let datetimeStr = parsed.targetDatetime {
                let isoFmt = DateFormatter()
                isoFmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                isoFmt.locale = Locale(identifier: "en_US_POSIX")
                targetDate = isoFmt.date(from: datetimeStr)
            }

            let intervalConfig: IntervalConfiguration
            if let targetDate = targetDate, targetDate > Date() {
                // Specific datetime intent → one-time non-repeating notification
                intervalConfig = IntervalConfiguration(type: .oneTime, targetDate: targetDate)
            } else {
                // No explicit datetime → fall back to interval-based cadence
                intervalConfig = convertMinutesToIntervalConfig(parsed.notificationInterval)
            }

            return ParsedArsenal(
                title: parsed.title,
                description: parsed.description,
                intervalConfig: intervalConfig,
                endDate: parsed.endDate
            )
        } catch {
            // Fallback to simple parsing
            return createFallback(from: originalInput)
        }
    }
    
    private func createFallback(from input: String) -> ParsedArsenal {
        // Simple fallback when AI parsing fails
        let title = String(input.prefix(50))
        let description = "Voice reminder: \(input)"

        // Default to 4 hours interval
        let intervalConfig = IntervalConfiguration(type: .hours, value: 4)

        return ParsedArsenal(
            title: title,
            description: description,
            intervalConfig: intervalConfig,
            endDate: nil
        )
    }
    
    /// Convert minutes to appropriate IntervalConfiguration
    private func convertMinutesToIntervalConfig(_ minutes: Int32) -> IntervalConfiguration {
        switch minutes {
        case 5, 15, 30:
            return IntervalConfiguration(type: .minutes, value: Int16(minutes))
        case 60, 120, 240, 360, 720:
            return IntervalConfiguration(type: .hours, value: Int16(minutes / 60))
        case 1440: // Daily
            return IntervalConfiguration.defaultDaily
        case 10080: // Weekly
            return IntervalConfiguration.defaultWeekly
        case 20160: // Biweekly (2 weeks)
            return IntervalConfiguration(type: .weekly, value: 2)
        case 43200: // Monthly (approximate)
            return IntervalConfiguration.defaultMonthly
        default:
            // Default to 4 hours
            return IntervalConfiguration(type: .hours, value: 4)
        }
    }
}

// MARK: - Models

struct ParsedArsenal {
    let title: String
    let description: String
    let intervalConfig: IntervalConfiguration
    /// Optional deadline date for the task (e.g. "remind me before Christmas")
    let endDate: Date?
}

private struct ParsedArsenalResponse: Codable {
    let title: String
    let description: String
    let endDate: Date?
    let notificationInterval: Int32
    /// ISO-8601 datetime string for an explicit one-time fire time (e.g. "2026-03-25T08:00:00")
    let targetDatetime: String?
}

enum SiriParserError: LocalizedError {
    case invalidResponse
    case parsingFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Could not parse voice command"
        case .parsingFailed:
            return "Failed to create reminder from voice input"
        }
    }
}

