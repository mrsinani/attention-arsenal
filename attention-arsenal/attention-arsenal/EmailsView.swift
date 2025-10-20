import SwiftUI

struct EmailsView: View {
    var body: some View {
        NavigationView {
            ComingSoonView()
                .navigationTitle("Emails")
                .navigationBarTitleDisplayMode(.large)
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Coming Soon View

struct ComingSoonView: View {
    var body: some View {
        VStack(spacing: 24) {
            // Simple black and white icon
            Image(systemName: "envelope.fill")
                .font(.system(size: 80))
                .foregroundColor(.primary)
            
            VStack(spacing: 12) {
                Text("Email Integration")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Coming Soon")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 16) {
                Text("We're working on bringing intelligent email reminders to Attention Arsenal.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                VStack(alignment: .center, spacing: 12) {
                    FeatureItem(
                        icon: "sparkles",
                        text: "AI-powered email analysis"
                    )
                    FeatureItem(
                        icon: "bell.badge",
                        text: "Smart reminder suggestions"
                    )
                    FeatureItem(
                        icon: "envelope.open",
                        text: "Gmail & Outlook support"
                    )
                }
                .padding(.top, 8)
            }
            
            Text("Stay tuned for updates!")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Feature Item

struct FeatureItem: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(.primary)
                .frame(width: 20)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }
}

#Preview {
    EmailsView()
}

