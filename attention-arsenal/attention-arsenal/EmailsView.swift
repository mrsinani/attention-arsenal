import SwiftUI

struct EmailsView: View {
    @EnvironmentObject var gmailAuthManager: GmailAuthManager
    @StateObject private var emailManager = EmailManager.shared
    @State private var selectedFilter: EmailFilter = .all
    
    var body: some View {
        NavigationView {
            Group {
                if gmailAuthManager.isLoading {
                    // Loading state while restoring session
                    ProgressView("Checking sign-in status...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !gmailAuthManager.isSignedIn {
                    // Not signed in - show sign-in prompt
                    GmailSignInView()
                } else {
                    // Signed in - show emails
                    EmailListView(
                        emails: filteredEmails,
                        isLoading: emailManager.isLoading,
                        errorMessage: emailManager.errorMessage,
                        selectedFilter: $selectedFilter,
                        onRefresh: { await loadEmails() }
                    )
                }
            }
            .navigationTitle("Emails")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if gmailAuthManager.isSignedIn {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            if let email = gmailAuthManager.userEmail {
                                Text(email)
                            }
                            Divider()
                            Button(role: .destructive) {
                                signOut()
                            } label: {
                                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                        } label: {
                            Image(systemName: "person.circle")
                                .font(.title3)
                        }
                    }
                }
            }
            .task {
                // Load emails when view appears and user is signed in
                if gmailAuthManager.isSignedIn && emailManager.emails.isEmpty {
                    await loadEmails()
                }
            }
            .onChange(of: gmailAuthManager.isSignedIn) { _, isSignedIn in
                if isSignedIn {
                    Task {
                        await loadEmails()
                    }
                } else {
                    emailManager.clearEmails()
                }
            }
        }
        .navigationViewStyle(.stack)
    }
    
    private var filteredEmails: [EmailMessage] {
        selectedFilter.filter(emailManager.emails)
    }
    
    private func loadEmails() async {
        await emailManager.fetchEmails(limit: 100)
    }
    
    private func signOut() {
        gmailAuthManager.signOut()
        emailManager.clearEmails()
    }
}

// MARK: - Gmail Sign-In View

struct GmailSignInView: View {
    @EnvironmentObject var gmailAuthManager: GmailAuthManager
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Icon
            Image(systemName: "envelope.fill")
                .font(.system(size: 80))
                .foregroundColor(.primary)
            
            // Title and description
            VStack(spacing: 12) {
                Text("Connect Gmail")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Sign in with your Google account to view your recent emails and get AI-powered reminder suggestions.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            // Sign-in button
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
                        Image(systemName: "envelope.badge.person.crop")
                            .font(.title3)
                    }
                    Text("Sign in with Google")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: 280)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(gmailAuthManager.isLoading)
            
            // Error message
            if let errorMessage = gmailAuthManager.errorMessage {
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
    let onRefresh: () async -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Filter picker
            Picker("Filter", selection: $selectedFilter) {
                ForEach(EmailFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.menu)
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
}
