import Foundation
import AppIntents

/// App Intent for adding arsenals via Siri
struct AddArsenalIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Arsenal"
    static var description = IntentDescription("Create a new reminder using natural language")
    
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = true
    
    @Parameter(title: "What to remember", requestValueDialog: "What would you like to be reminded about?")
    var reminderText: String
    
    static var parameterSummary: some ParameterSummary {
        Summary("Add arsenal for \(\.$reminderText)")
    }
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Parse the voice input using AI
        let parsedArsenal: ParsedArsenal
        
        do {
            parsedArsenal = try await SiriArsenalParser.shared.parseVoiceInput(reminderText)
        } catch {
            // If parsing fails, return error
            return .result(
                dialog: IntentDialog(stringLiteral: "Sorry, I couldn't create that reminder. Please try again.")
            )
        }
        
        // Create the arsenal
        let arsenalManager = ArsenalManager(
            context: PersistenceController.shared.container.viewContext
        )
        
        let arsenal = arsenalManager.createArsenal(
            title: parsedArsenal.title,
            description: parsedArsenal.description,
            startDate: parsedArsenal.startDate,
            endDate: parsedArsenal.endDate,
            notificationInterval: parsedArsenal.notificationInterval
        )
        
        // Generate response message
        let responseMessage: String
        if arsenal != nil {
            if let endDate = parsedArsenal.endDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                let endDateString = formatter.string(from: endDate)
                responseMessage = "Added reminder for \(parsedArsenal.title) until \(endDateString)"
            } else {
                responseMessage = "Added reminder: \(parsedArsenal.title)"
            }
        } else {
            responseMessage = "Sorry, I couldn't create that reminder"
        }
        
        return .result(dialog: IntentDialog(stringLiteral: responseMessage))
    }
}

// Note: App Shortcuts are defined in ShortcutsProvider.swift for better organization

