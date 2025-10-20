import Foundation
import MessageUI

/// Manager for accessing and displaying emails
class EmailManager: ObservableObject {
    static let shared = EmailManager()
    
    @Published var emails: [EmailMessage] = []
    @Published var isAvailable: Bool = false
    
    private init() {
        // Check if Mail is available
        isAvailable = MFMailComposeViewController.canSendMail()
    }
    
    /// Fetch recent emails
    /// Note: iOS doesn't provide direct API access to read emails from the Mail app
    /// This creates mock data for demonstration. In production, you would:
    /// 1. Use a mail API (Gmail, Outlook, etc.) with OAuth
    /// 2. Use server-side email fetching
    /// 3. Use MailKit on macOS (not available on iOS)
    func fetchEmails(limit: Int = 30) async {
        // For now, we'll create sample emails to demonstrate the UI
        // In a real app, you'd integrate with email services via their APIs
        let sampleEmails = createSampleEmails(count: limit)
        
        await MainActor.run {
            self.emails = sampleEmails
        }
    }
    
    /// Create sample emails for demonstration
    private func createSampleEmails(count: Int) -> [EmailMessage] {
        let subjects = [
            "Team Meeting Tomorrow at 2 PM",
            "Project Deadline Reminder",
            "Review Required: Q4 Report",
            "Dinner Plans This Friday?",
            "Conference Registration Confirmation",
            "Weekly Status Update Due",
            "Client Presentation Feedback",
            "Doctor Appointment Confirmation",
            "Gym Membership Renewal",
            "Book Club Meeting Next Week"
        ]
        
        let senders = [
            "Sarah Johnson",
            "Mike Chen",
            "Emily Davis",
            "Alex Rodriguez",
            "Jessica Lee",
            "David Park",
            "Rachel Kim",
            "Dr. Smith",
            "FitLife Gym",
            "Book Club"
        ]
        
        let bodies = [
            "Hi team, just a reminder about our meeting tomorrow at 2 PM to discuss the quarterly goals.",
            "The project deadline is coming up next week. Please make sure all deliverables are ready.",
            "Could you please review the Q4 report and provide your feedback by end of week?",
            "Hey! Are you free for dinner this Friday? Let me know what works for you.",
            "Your registration for the tech conference has been confirmed. Event starts on March 15th.",
            "Please submit your weekly status update by Friday EOD.",
            "The client loved the presentation! They have a few minor changes they'd like to discuss.",
            "Your appointment is scheduled for January 25th at 10:00 AM. Please arrive 15 minutes early.",
            "Your gym membership is expiring soon. Renew now to continue enjoying our facilities.",
            "Our next book club meeting is scheduled for next Tuesday at 7 PM."
        ]
        
        var emails: [EmailMessage] = []
        let now = Date()
        
        for i in 0..<min(count, subjects.count) {
            // Create emails with varying dates in the past
            let daysAgo = Double(i) * 0.5
            let emailDate = Calendar.current.date(byAdding: .hour, value: -Int(daysAgo * 24), to: now) ?? now
            
            let email = EmailMessage(
                id: UUID().uuidString,
                subject: subjects[i],
                sender: senders[i],
                body: bodies[i],
                date: emailDate,
                isRead: i > 3 // Mark first few as unread
            )
            emails.append(email)
        }
        
        return emails
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

