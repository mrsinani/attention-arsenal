import SwiftUI
import CoreData

// MARK: - Email Provider Enum

enum EmailProvider: String, CaseIterable {
    case gmail = "Gmail"
    case outlook = "Outlook"
    
    var icon: String {
        switch self {
        case .gmail: return "envelope.fill"
        case .outlook: return "envelope.badge.person.crop.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .gmail: return .red
        case .outlook: return .blue
        }
    }
}

// MARK: - Main Emails View

struct EmailsView: View {
    @EnvironmentObject var gmailAuthManager: GmailAuthManager
    @EnvironmentObject var outlookAuthManager: OutlookAuthManager
    @StateObject private var emailManager = EmailManager.shared
    @StateObject private var arsenalManager = ArsenalManager()
    
    @State private var activeProvider: EmailProvider?
    
    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Checking sign-in status...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if activeProvider == nil {
                    // Show provider selection
                    EmailProviderSelectionView()
                } else {
                    // Show emails list
                    EmailsListView(
                        emails: emailManager.emails,
                        isLoading: emailManager.isLoading,
                        errorMessage: emailManager.errorMessage,
                        provider: activeProvider!,
                        arsenalManager: arsenalManager,
                        onRefresh: { await refreshEmails() },
                        onSignOut: { signOut() }
                    )
                }
            }
            .navigationTitle("Emails")
            .navigationBarTitleDisplayMode(.large)
            .task {
                updateActiveProvider()
                if activeProvider != nil && emailManager.emails.isEmpty {
                    await refreshEmails()
                }
            }
            // Gmail onChange disabled for now
            .onChange(of: outlookAuthManager.isSignedIn) { _, isSignedIn in
                if isSignedIn {
                    activeProvider = .outlook
                    Task { await refreshEmails() }
                } else if activeProvider == .outlook {
                    resetState()
                }
            }
        }
        .navigationViewStyle(.stack)
    }
    
    private var isLoading: Bool {
        outlookAuthManager.isLoading
    }
    
    private func updateActiveProvider() {
        // Gmail disabled for now - only check Outlook
        if outlookAuthManager.isSignedIn {
            activeProvider = .outlook
        } else {
            activeProvider = nil
        }
    }
    
    private func refreshEmails() async {
        guard activeProvider == .outlook else { return }
        
        // Gmail disabled for now - only fetch Outlook
        await emailManager.fetchOutlookEmails(limit: 50)
    }
    
    private func signOut() {
        // Gmail disabled for now - only handle Outlook
        if activeProvider == .outlook {
            outlookAuthManager.signOut()
        }
        resetState()
    }
    
    private func resetState() {
        activeProvider = nil
        emailManager.clearEmails()
    }
}

// MARK: - Email Provider Selection View

struct EmailProviderSelectionView: View {
    @EnvironmentObject var gmailAuthManager: GmailAuthManager
    @EnvironmentObject var outlookAuthManager: OutlookAuthManager
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 80))
                .foregroundColor(.primary)
            
            VStack(spacing: 12) {
                Text("Email Reminders")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Connect your email to create AI-powered reminders for emails that need follow-up.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            VStack(spacing: 16) {
                Button {
                    Task { await outlookAuthManager.signIn() }
                } label: {
                    HStack(spacing: 12) {
                        if outlookAuthManager.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "envelope.badge.person.crop.fill")
                                .font(.title3)
                        }
                        Text("Continue with Outlook")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: 280)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(outlookAuthManager.isLoading)
                
                // Gmail - Coming Soon
                VStack(spacing: 4) {
                    HStack(spacing: 12) {
                        Image(systemName: "envelope.fill")
                            .font(.title3)
                        Text("Continue with Gmail")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: 280)
                    .padding()
                    .background(Color.gray.opacity(0.3))
                    .foregroundColor(.gray)
                    .cornerRadius(12)
                    
                    Text("Coming Soon")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if let error = outlookAuthManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Text("Click + on any email to create an AI-powered reminder.\nYour data stays on your device.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
        }
        .padding()
    }
}

// MARK: - Emails List View

struct EmailsListView: View {
    let emails: [EmailMessage]
    let isLoading: Bool
    let errorMessage: String?
    let provider: EmailProvider
    let arsenalManager: ArsenalManager
    let onRefresh: () async -> Void
    let onSignOut: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Provider badge header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: provider.icon)
                        .font(.caption)
                    Text(provider.rawValue)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(provider.color.opacity(0.15))
                .foregroundColor(provider.color)
                .cornerRadius(8)
                
                Spacer()
                
                Text("\(emails.count) emails")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Divider()
            
            // Content
            if isLoading && emails.isEmpty {
                ProgressView("Fetching emails...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage, emails.isEmpty {
                ScrollView {
                    ErrorStateView(message: error, onRetry: {
                        Task { await onRefresh() }
                    })
                }
                .refreshable {
                    await onRefresh()
                }
            } else if emails.isEmpty {
                ScrollView {
                    EmptyEmailsView()
                }
                .refreshable {
                    await onRefresh()
                }
            } else {
                List {
                    ForEach(groupedEmails, id: \.date) { group in
                        Section(header: Text(group.title)) {
                            ForEach(group.emails) { email in
                                EmailRow(
                                    email: email,
                                    arsenalManager: arsenalManager
                                )
                            }
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
                .refreshable {
                    await onRefresh()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Text("Connected to \(provider.rawValue)")
                    Divider()
                    Button(role: .destructive, action: onSignOut) {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "person.circle")
                        .font(.title3)
                }
            }
        }
    }
    
    // Group emails by day
    private var groupedEmails: [EmailGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: emails) { email in
            calendar.startOfDay(for: email.date)
        }
        
        return grouped.map { date, emails in
            EmailGroup(date: date, emails: emails)
        }.sorted { $0.date > $1.date } // Most recent first
    }
}

struct EmailGroup {
    let date: Date
    let emails: [EmailMessage]
    
    var title: String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let emailDate = calendar.startOfDay(for: date)
        
        if emailDate == today {
            return "Today"
        } else if emailDate == calendar.date(byAdding: .day, value: -1, to: today) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }
}

// MARK: - Email Row

struct EmailRow: View {
    let email: EmailMessage
    let arsenalManager: ArsenalManager
    
    @State private var isCreatingReminder = false
    @State private var showSuccessMessage = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var isHidden = false
    
    var body: some View {
        if !isHidden {
            emailContent
        }
    }
    
    private var emailContent: some View {
        HStack(alignment: .top, spacing: 12) {
            // Unread indicator
            Circle()
                .fill(email.isRead ? Color.clear : Color.blue)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            
            VStack(alignment: .leading, spacing: 6) {
                // Sender
                Text(email.sender)
                    .font(.body)
                    .fontWeight(email.isRead ? .regular : .semibold)
                    .lineLimit(1)
                
                // Subject
                Text(email.subject)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                // Preview
                Text(email.body)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                // Time
                Text(timeAgo(from: email.date))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Add Reminder Button
            Button(action: {
                createAIReminder()
            }) {
                if isCreatingReminder {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if showSuccessMessage {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                } else {
                    VStack(spacing: 2) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                        Text("Add")
                            .font(.caption2)
                    }
                    .foregroundColor(.blue)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isCreatingReminder || showSuccessMessage)
        }
        .padding(.vertical, 4)
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    /// Convert minutes to appropriate IntervalConfiguration
    private func convertMinutesToIntervalConfig(_ minutes: Int32) -> IntervalConfiguration {
        switch minutes {
        case 5, 15, 30:
            return IntervalConfiguration(type: .minutes, value: Int16(minutes))
        case 60, 120, 240, 360, 720:
            return IntervalConfiguration(type: .hours, value: Int16(minutes / 60))
        case 1440:
            return IntervalConfiguration.defaultDaily
        default:
            return IntervalConfiguration(type: .hours, value: 4)
        }
    }
    
    private func createAIReminder() {
        isCreatingReminder = true
        
        Task {
            do {
                // Generate reminder using AI
                let suggestion = try await AIEmailReminderService.shared.generateReminder(for: email)
                
                // Create the arsenal with suggested details
                await MainActor.run {
                    let intervalConfig = convertMinutesToIntervalConfig(suggestion.notificationInterval)
                    
                    let arsenal = arsenalManager.createArsenal(
                        title: suggestion.title,
                        description: suggestion.description,
                        intervalConfig: intervalConfig
                    )
                    
                    isCreatingReminder = false
                    
                    if arsenal != nil {
                        // Show success briefly
                        showSuccessMessage = true
                        
                        // Hide the email after showing success
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation {
                                isHidden = true
                            }
                        }
                    } else {
                        errorMessage = "Failed to create reminder"
                        showErrorAlert = true
                    }
                }
            } catch {
                await MainActor.run {
                    isCreatingReminder = false
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
            }
        }
    }
}

// MARK: - Empty State

struct EmptyEmailsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "tray")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Emails")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Your inbox appears to be empty.\nPull down to refresh.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Error State

struct ErrorStateView: View {
    let message: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("Something Went Wrong")
                .font(.title2)
                .fontWeight(.medium)
            
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button(action: onRetry) {
                Text("Try Again")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Gmail Code (Disabled - Uncomment to re-enable)
/*
 
// To re-enable Gmail, replace the relevant sections with this code:

// 1. In EmailsView - updateActiveProvider():
private func updateActiveProvider() {
    if gmailAuthManager.isSignedIn {
        activeProvider = .gmail
    } else if outlookAuthManager.isSignedIn {
        activeProvider = .outlook
    } else {
        activeProvider = nil
    }
}

// 2. In EmailsView - isLoading:
private var isLoading: Bool {
    gmailAuthManager.isLoading || outlookAuthManager.isLoading
}

// 3. In EmailsView - add this onChange after .task:
.onChange(of: gmailAuthManager.isSignedIn) { _, isSignedIn in
    if isSignedIn {
        activeProvider = .gmail
        Task { await refreshEmails() }
    } else if activeProvider == .gmail {
        resetState()
    }
}

// 4. In EmailsView - refreshEmails():
private func refreshEmails() async {
    guard let provider = activeProvider else { return }
    
    switch provider {
    case .gmail:
        await emailManager.fetchGmailEmails(limit: 50)
    case .outlook:
        await emailManager.fetchOutlookEmails(limit: 50)
    }
}

// 5. In EmailsView - signOut():
private func signOut() {
    switch activeProvider {
    case .gmail:
        gmailAuthManager.signOut()
    case .outlook:
        outlookAuthManager.signOut()
    case .none:
        break
    }
    resetState()
}

// 6. In EmailProviderSelectionView - Gmail button (replace the Coming Soon section):
Button {
    Task { await gmailAuthManager.signIn() }
} label: {
    HStack(spacing: 12) {
        if gmailAuthManager.isLoading {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
        } else {
            Image(systemName: "envelope.fill")
                .font(.title3)
        }
        Text("Continue with Gmail")
            .fontWeight(.semibold)
    }
    .frame(maxWidth: 280)
    .padding()
    .background(Color.red.opacity(0.9))
    .foregroundColor(.white)
    .cornerRadius(12)
}
.disabled(gmailAuthManager.isLoading || outlookAuthManager.isLoading)

// 7. In EmailProviderSelectionView - error message:
if let error = gmailAuthManager.errorMessage ?? outlookAuthManager.errorMessage {

*/

#Preview {
    EmailsView()
        .environmentObject(GmailAuthManager.shared)
        .environmentObject(OutlookAuthManager.shared)
}
