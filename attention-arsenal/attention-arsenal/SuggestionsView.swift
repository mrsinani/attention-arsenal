import SwiftUI

struct SuggestionsView: View {
    @EnvironmentObject var suggestionManager: AISuggestionManager
    @EnvironmentObject var arsenalManager: ArsenalManager
    @State private var showingAcceptedAlert = false
    @State private var acceptedSuggestionTitle = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                if suggestionManager.suggestions.isEmpty && !suggestionManager.isLoading {
                    EmptySuggestionsView()
                } else {
                    suggestionsList
                }
                
                if suggestionManager.isLoading {
                    ProgressView("Loading suggestions...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemBackground).opacity(0.8))
                }
            }
            .navigationTitle("AI Suggestions")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        suggestionManager.refreshSuggestions()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.title2)
                    }
                    .disabled(suggestionManager.isLoading)
                }
            }
            .alert("Suggestion Added", isPresented: $showingAcceptedAlert) {
                Button("OK") { }
            } message: {
                Text("'\(acceptedSuggestionTitle)' has been added to your arsenal!")
            }
        }
    }
    
    private var suggestionsList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(suggestionManager.suggestions) { suggestion in
                    SuggestionCard(
                        suggestion: suggestion,
                        onAccept: {
                            acceptSuggestion(suggestion)
                        },
                        onDecline: {
                            suggestionManager.declineSuggestion(suggestion)
                        }
                    )
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .refreshable {
            suggestionManager.refreshSuggestions()
        }
    }
    
    private func acceptSuggestion(_ suggestion: AISuggestion) {
        acceptedSuggestionTitle = suggestion.title
        suggestionManager.acceptSuggestion(suggestion)
        showingAcceptedAlert = true
    }
}

struct SuggestionCard: View {
    let suggestion: AISuggestion
    let onAccept: () -> Void
    let onDecline: () -> Void
    
    @State private var isAnimating = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with priority and source
            HStack {
                // Priority indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(suggestion.priority.color)
                        .frame(width: 8, height: 8)
                    Text(suggestion.priority.rawValue)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(suggestion.priority.color)
                }
                
                Spacer()
                
                // Estimated duration
                if let duration = suggestion.estimatedDuration {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption)
                        Text(formatDuration(duration))
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
            }
            
            // Main content
            VStack(alignment: .leading, spacing: 8) {
                Text(suggestion.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                if let description = suggestion.description {
                    Text(description)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            // Action buttons
            HStack(spacing: 12) {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isAnimating = true
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        onAccept()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add to Arsenal")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .cornerRadius(20)
                }
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        onDecline()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle")
                        Text("Dismiss")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(20)
                }
            }
            
            // Source attribution
            HStack(spacing: 6) {
                Image(systemName: suggestion.suggestedBy.icon)
                    .font(.caption)
                    .foregroundColor(suggestion.suggestedBy.color)
                
                Text("Suggested by \(suggestion.suggestedBy.rawValue)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let context = suggestion.context {
                    Text("• \(context)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
        .scaleEffect(isAnimating ? 0.95 : 1.0)
        .opacity(isAnimating ? 0.8 : 1.0)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

struct EmptySuggestionsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Suggestions Yet")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            Text("AI suggestions will appear here based on your emails, calendar, and usage patterns.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button("Refresh Suggestions") {
                // This would trigger a refresh in the parent view
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    SuggestionsView()
        .environmentObject(ArsenalManager())
        .environmentObject(AISuggestionManager())
}
