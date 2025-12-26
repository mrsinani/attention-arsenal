import SwiftUI

struct StatsView: View {
    @StateObject private var statsManager = StatsManager.shared
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Main stats grid
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        StatCard(
                            title: "Total Completed",
                            value: "\(statsManager.totalCompleted)",
                            icon: "checkmark.circle.fill",
                            color: .green
                        )
                        
                        StatCard(
                            title: "This Week",
                            value: "\(statsManager.completedThisWeek)",
                            icon: "calendar",
                            color: .blue
                        )
                        
                        StatCard(
                            title: "Current Streak",
                            value: "\(statsManager.currentStreak)",
                            subtitle: statsManager.currentStreak == 1 ? "day" : "days",
                            icon: "flame.fill",
                            color: .orange
                        )
                        
                        StatCard(
                            title: "Longest Streak",
                            value: "\(statsManager.longestStreak)",
                            subtitle: statsManager.longestStreak == 1 ? "day" : "days",
                            icon: "trophy.fill",
                            color: .yellow
                        )
                    }
                    .padding(.horizontal)
                    
                    // Motivational message
                    if statsManager.currentStreak > 0 {
                        StreakMessageView(streak: statsManager.currentStreak)
                            .padding(.horizontal)
                    }
                    
                    Spacer()
                }
                .padding(.top, 20)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.large)
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Stat Card
struct StatCard: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(color)
            
            // Value
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            // Title
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 12)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
}

// MARK: - Streak Message
struct StreakMessageView: View {
    let streak: Int
    
    var message: String {
        switch streak {
        case 1:
            return "Great start! Keep it going! 🌱"
        case 2...3:
            return "You're building momentum! 💪"
        case 4...6:
            return "Impressive streak! Stay focused! 🔥"
        case 7...13:
            return "A whole week! You're unstoppable! 🚀"
        case 14...29:
            return "Two weeks strong! Amazing! ⭐"
        case 30...59:
            return "A month of consistency! Legendary! 🏆"
        default:
            return "You're a productivity master! 👑"
        }
    }
    
    var body: some View {
        HStack {
            Text(message)
                .font(.body)
                .foregroundColor(.primary)
            
            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.15))
        .cornerRadius(12)
    }
}

#Preview {
    StatsView()
}

