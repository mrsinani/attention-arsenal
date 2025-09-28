import SwiftUI

struct MainTabView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var arsenalManager = ArsenalManager()
    @StateObject private var suggestionManager = AISuggestionManager()
    @EnvironmentObject var notificationManager: NotificationManager
    
    var body: some View {
        TabView {
            // Home Tab (existing arsenal list)
            ContentView()
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("Home")
                }
            
            // AI Suggestions Tab
            SuggestionsView()
                .tabItem {
                    Image(systemName: "brain.head.profile")
                    Text("Suggestions")
                }
        }
        .environmentObject(arsenalManager)
        .environmentObject(suggestionManager)
        .accentColor(.blue)
    }
}

#Preview {
    MainTabView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(NotificationManager.shared)
}
