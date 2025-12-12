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
        - An end date ONLY if a specific date/event is mentioned (null otherwise)
        - Appropriate notification interval in minutes
        
        Date parsing rules for END DATE:
        - "tomorrow" = tomorrow's date
        - "next Friday", "this weekend" = calculate specific date
        - "in 3 days", "in 2 weeks" = calculate from today
        - "January 15", "Dec 25th" = specific date this year or next if passed
        - "Halloween" = October 31
        - "Christmas" = December 25
        - NO specific date mentioned = null
        
        IMPORTANT: Arsenals start immediately when created. Only extract the END date if a specific event date is mentioned.
        
        Notification intervals (in minutes): 5, 15, 30, 60, 120, 240, 360, 720, 1440 (daily), 10080 (weekly), 20160 (biweekly), 43200 (monthly)
        Choose based on urgency:
        - Urgent/Soon: 30-60
        - This week: 120-240
        - Near future: 360-1440
        - Regular reminders: 10080 (weekly) or 20160 (biweekly)
        - Long-term: 43200 (monthly)
        
        Respond with this EXACT JSON format:
        {
          "title": "short title here",
          "description": "helpful description",
          "endDate": "2025-01-25" or null,
          "notificationInterval": 240
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
                
                // Try to parse the date
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
            
            // Convert notification interval to IntervalConfiguration
            let intervalConfig = convertMinutesToIntervalConfig(parsed.notificationInterval)
            
            return ParsedArsenal(
                title: parsed.title,
                description: parsed.description,
                intervalConfig: intervalConfig
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
            intervalConfig: intervalConfig
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
}

private struct ParsedArsenalResponse: Codable {
    let title: String
    let description: String
    let endDate: Date?
    let notificationInterval: Int32
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

