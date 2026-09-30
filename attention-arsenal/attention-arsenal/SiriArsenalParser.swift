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

        do {
            let response = try await OpenAIService.shared.sendPrompt(prompt)
            return try parseResponse(response, originalInput: voiceInput)
        } catch {
            // The AI is an enhancement, not a dependency: a missing key, an exhausted quota,
            // no signal, or a timeout inside Siri's short budget all land here. Parsing
            // locally keeps "Hey Siri, add arsenal" working instead of answering
            // "Sorry, I couldn't create that reminder."
            #if DEBUG
            print("Siri parse fell back to local parsing: \(error.localizedDescription)")
            #endif
            return createFallback(from: voiceInput)
        }
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
                // No explicit datetime → fall back to interval-based cadence, then restore the
                // time the user actually said (the AI reports cadence only).
                intervalConfig = Self.applySpokenTime(
                    to: convertMinutesToIntervalConfig(parsed.notificationInterval),
                    from: originalInput
                )
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
    
    /// Offline parse of a voice command. `NSDataDetector` is the system's own date parser —
    /// the one that turns "tomorrow at 3pm" into a date in Mail — so this needs no grammar of
    /// its own. Internal (not private) so tests can drive the offline path directly.
    func createFallback(from input: String) -> ParsedArsenal {
        let lowercased = input.lowercased()
        let (detectedDate, remainder) = Self.detectDate(in: input)
        let title = Self.cleanedTitle(from: remainder.isEmpty ? input : remainder)

        let intervalConfig: IntervalConfiguration
        if Self.mentionsRepetition(lowercased) {
            // "every day at 9am" — recurring, with the spoken time if one was detected.
            var config = Self.repeatingConfig(for: lowercased)
            if let detectedDate {
                let time = Calendar.current.dateComponents([.hour, .minute], from: detectedDate)
                config.hour = Int16(time.hour ?? 9)
                config.minute = Int16(time.minute ?? 0)
            }
            intervalConfig = config
        } else if let detectedDate, detectedDate > Date() {
            // "dentist tomorrow at 3pm" — a single fire at the moment the user named.
            intervalConfig = IntervalConfiguration(type: .oneTime, targetDate: detectedDate)
        } else {
            // Nothing to go on: reuse whatever cadence this user actually picks, never .none —
            // a Siri reminder that can't fire is worse than a wrong interval.
            let last = IntervalConfiguration.lastUsed
            intervalConfig = last.type == .none ? .defaultDaily : last
        }

        return ParsedArsenal(
            title: title,
            description: "Voice reminder: \(input)",
            intervalConfig: intervalConfig,
            endDate: nil
        )
    }

    /// Restore the clock time (and weekday) the user spoke onto a recurring config.
    /// The AI only reports a cadence in minutes, so "every day at 6pm" came back as 1440 and
    /// landed on `defaultDaily` — 9:00 AM. The spoken time is right there in the input, so
    /// read it with the same detector the offline path uses.
    static func applySpokenTime(to config: IntervalConfiguration, from input: String) -> IntervalConfiguration {
        guard config.type.needsTimeSelection, let spoken = detectDate(in: input).date else {
            return config
        }

        var updated = config
        let spokenParts = Calendar.current.dateComponents([.hour, .minute, .weekday], from: spoken)
        updated.hour = Int16(spokenParts.hour ?? Int(config.hour))
        updated.minute = Int16(spokenParts.minute ?? Int(config.minute))

        // Only move the weekday when the user actually named one: a bare "every day at 6pm"
        // resolves to today, which would silently turn a weekly reminder into a today-only one.
        if config.type == .weekly,
           let weekdayNumber = spokenParts.weekday,
           let weekday = Weekday(rawValue: weekdayNumber - 1),
           input.range(of: weekday.fullName, options: .caseInsensitive) != nil {
            var days = DaysBitmask()
            days.set(weekday, selected: true)
            updated.days = days
        }

        return updated
    }

    // MARK: - Local Parsing Helpers

    private static let leadingPhrases = [
        "remind me to ", "remind me ", "remember to ", "remember ",
        "add an arsenal to ", "add an arsenal for ", "add arsenal to ", "add arsenal for ",
        "create an arsenal to ", "create arsenal to ", "create arsenal for ",
        "new arsenal to ", "new arsenal for ", "i need to ", "make sure to "
    ]

    private static let repetitionPhrases = [
        "every day", "everyday", "daily", "every morning", "every night", "every evening",
        "every week", "weekly", "every month", "monthly"
    ]

    static func mentionsRepetition(_ lowercased: String) -> Bool {
        repetitionPhrases.contains { lowercased.contains($0) }
    }

    static func repeatingConfig(for lowercased: String) -> IntervalConfiguration {
        if lowercased.contains("every month") || lowercased.contains("monthly") {
            return .defaultMonthly
        }
        if lowercased.contains("every week") || lowercased.contains("weekly") {
            return .defaultWeekly
        }
        return .defaultDaily
    }

    /// First date/time in the text, plus the text with that phrase removed.
    static func detectDate(in input: String) -> (date: Date?, remainder: String) {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return (nil, input)
        }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        guard let match = detector.matches(in: input, range: range).first,
              let date = match.date,
              let matchRange = Range(match.range, in: input) else {
            return (nil, input)
        }
        var remainder = input
        remainder.removeSubrange(matchRange)
        return (date, remainder.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Strip the command scaffolding ("remind me to ...") and any dangling preposition left
    /// behind by removing the date phrase, so the title reads like a task.
    static func cleanedTitle(from text: String) -> String {
        var title = text.trimmingCharacters(in: .whitespacesAndNewlines)

        for phrase in leadingPhrases where title.lowercased().hasPrefix(phrase) {
            title = String(title.dropFirst(phrase.count))
            break
        }

        let fillers = ["every day", "everyday", "daily", "every week", "weekly", "every month", "monthly"]
        for filler in fillers {
            if let found = title.range(of: filler, options: [.caseInsensitive]) {
                title.removeSubrange(found)
            }
        }

        title = title.trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?"))
        for preposition in ["on", "at", "by", "in", "this", "next"] where
            title.lowercased().hasSuffix(" " + preposition) {
            title = String(title.dropLast(preposition.count + 1))
            break
        }

        title = title.trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?"))
        guard !title.isEmpty else { return "Reminder" }
        return String(title.prefix(50)).prefix(1).uppercased() + String(title.prefix(50)).dropFirst()
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

