import SwiftUI

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
    @State private var selectedFilter: EmailFilter = .all
    @State private var activeProvider: EmailProvider?
    
    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Checking sign-in status...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let provider = activeProvider {
                    // Show emails for the active provider
                    EmailListView(
                        emails: filteredEmails,
                        isLoading: emailManager.isLoading,
                        errorMessage: emailManager.errorMessage,
                        selectedFilter: $selectedFilter,
                        provider: provider,
                        onRefresh: { await loadEmails(for: provider) },
                        onSignOut: { signOut(from: provider) }
                    )
                } else {
                    // Show provider selection
                    EmailProviderSelectionView()
                }
            }
            .navigationTitle("Emails")
            .navigationBarTitleDisplayMode(.large)
            .task {
                // Determine which provider is active
                updateActiveProvider()
                
                // Load emails if a provider is active
                if let provider = activeProvider, emailManager.emails.isEmpty {
                    await loadEmails(for: provider)
                }
            }
            .onChange(of: gmailAuthManager.isSignedIn) { _, isSignedIn in
                if isSignedIn {
                    activeProvider = .gmail
                    Task {
                        await loadEmails(for: .gmail)
                    }
                } else if activeProvider == .gmail {
                    activeProvider = nil
                    emailManager.clearEmails()
                }
            }
            .onChange(of: outlookAuthManager.isSignedIn) { _, isSignedIn in
                if isSignedIn {
                    activeProvider = .outlook
                    Task {
                        await loadEmails(for: .outlook)
                    }
                } else if activeProvider == .outlook {
                    activeProvider = nil
                    emailManager.clearEmails()
                }
            }
        }
        .navigationViewStyle(.stack)
    }
    
    private var isLoading: Bool {
        gmailAuthManager.isLoading || outlookAuthManager.isLoading
    }
    
    private var filteredEmails: [EmailMessage] {
        selectedFilter.filter(emailManager.emails)
    }
    
    private func updateActiveProvider() {
        if gmailAuthManager.isSignedIn {
            activeProvider = .gmail
        } else if outlookAuthManager.isSignedIn {
            activeProvider = .outlook
        } else {
            activeProvider = nil
        }
    }
    
    private func loadEmails(for provider: EmailProvider) async {
        switch provider {
        case .gmail:
            await emailManager.fetchGmailEmails(limit: 100)
        case .outlook:
            await emailManager.fetchOutlookEmails(limit: 100)
        }
    }
    
    private func signOut(from provider: EmailProvider) {
        switch provider {
        case .gmail:
            gmailAuthManager.signOut()
        case .outlook:
            outlookAuthManager.signOut()
        }
        emailManager.clearEmails()
        activeProvider = nil
    }
}

// MARK: - Email Provider Selection View

struct EmailProviderSelectionView: View {
    @EnvironmentObject var gmailAuthManager: GmailAuthManager
    @EnvironmentObject var outlookAuthManager: OutlookAuthManager
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Icon
            Image(systemName: "envelope.fill")
                .font(.system(size: 80))
                .foregroundColor(.primary)
            
            // Title and description
            VStack(spacing: 12) {
                Text("Connect Email")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Sign in with your email provider to view recent emails and get AI-powered reminder suggestions.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            // Provider buttons
            VStack(spacing: 16) {
                // Gmail button
                Button {
                    Task {
                        await gmailAuthManager.signIn()
                    }
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
                
                // Outlook button
                Button {
                    Task {
                        await outlookAuthManager.signIn()
                    }
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
                .disabled(gmailAuthManager.isLoading || outlookAuthManager.isLoading)
            }
            
            // Error messages
            if let errorMessage = gmailAuthManager.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            if let errorMessage = outlookAuthManager.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            // Privacy note
            VStack(spacing: 8) {
                Text("We only read your emails to suggest reminders.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("Your data stays on your device.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
    }
}

// MARK: - Email List View

struct EmailListView: View {
    let emails: [EmailMessage]
    let isLoading: Bool
    let errorMessage: String?
    @Binding var selectedFilter: EmailFilter
    let provider: EmailProvider
    let onRefresh: () async -> Void
    let onSignOut: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Provider indicator and filter
            HStack {
                // Provider badge
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
                
                // Filter picker
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(EmailFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.menu)
            }
            .padding()
            
            Divider()
            
            // Content
            if isLoading && emails.isEmpty {
                ProgressView("Loading emails...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = errorMessage, emails.isEmpty {
                ErrorView(message: errorMessage, onRetry: {
                    Task { await onRefresh() }
                })
            } else if emails.isEmpty {
                EmptyEmailsView(filter: selectedFilter)
            } else {
                List {
                    ForEach(emails) { email in
                        EmailRow(email: email)
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
                    Text("Signed in to \(provider.rawValue)")
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
}

// MARK: - Email Row

struct EmailRow: View {
    let email: EmailMessage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Sender and date
            HStack {
                Text(email.sender)
                    .font(.subheadline)
                    .fontWeight(email.isRead ? .regular : .semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Spacer()
                
                Text(formatDate(email.date))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Subject
            Text(email.subject)
                .font(.body)
                .fontWeight(email.isRead ? .regular : .medium)
                .foregroundColor(.primary)
                .lineLimit(2)
            
            // Unread indicator
            if !email.isRead {
                HStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                    Text("Unread")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if let daysAgo = calendar.dateComponents([.day], from: date, to: Date()).day, daysAgo < 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: date)
        }
    }
}

// MARK: - Empty State

struct EmptyEmailsView: View {
    let filter: EmailFilter
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "tray")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Emails")
                .font(.title2)
                .fontWeight(.medium)
            
            Text(emptyMessage)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var emptyMessage: String {
        switch filter {
        case .all:
            return "No emails found in your inbox."
        case .unread:
            return "You're all caught up! No unread emails."
        case .recent:
            return "No emails from the last 7 days."
        case .lastMonth:
            return "No emails from the last month."
        }
    }
}

// MARK: - Error View

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("Unable to Load Emails")
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

#Preview {
    EmailsView()
        .environmentObject(GmailAuthManager.shared)
        .environmentObject(OutlookAuthManager.shared)
}
