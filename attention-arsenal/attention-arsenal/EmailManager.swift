import Foundation

/// Manager for accessing and displaying emails via Gmail API
class EmailManager: ObservableObject {
    static let shared = EmailManager()
    
    @Published var emails: [EmailMessage] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    private init() {}
    
    /// Fetch recent emails from Gmail
    /// - Parameter limit: Maximum number of emails to fetch (default: 100)
    func fetchEmails(limit: Int = 100) async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        do {
            let fetchedEmails = try await GmailService.shared.fetchEmails(maxResults: limit)
            
            await MainActor.run {
                self.emails = fetchedEmails
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    /// Clear all emails (used when signing out)
    @MainActor
    func clearEmails() {
        emails = []
        errorMessage = nil
    }
}

/// Email filter options
enum EmailFilter: String, CaseIterable, Identifiable {
    case all = "All Emails"
    case unread = "Unread Only"
    case recent = "Last 7 Days"
    case lastMonth = "Last Month"
    
    var id: String { rawValue }
    
    /// Filter emails based on the selected filter
    func filter(_ emails: [EmailMessage]) -> [EmailMessage] {
        switch self {
        case .all:
            return emails
        case .unread:
            return emails.filter { !$0.isRead }
        case .recent:
            let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            return emails.filter { $0.date >= sevenDaysAgo }
        case .lastMonth:
            let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            return emails.filter { $0.date >= thirtyDaysAgo }
        }
    }
}

/// Email message model
struct EmailMessage: Identifiable {
    let id: String
    let subject: String
    let sender: String
    let body: String
    let date: Date
    let isRead: Bool
}

