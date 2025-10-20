import Foundation
import AppIntents

/// Provides app shortcuts that will appear in Settings > Siri & Search
struct AttentionArsenalShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddArsenalIntent(),
            phrases: [
                "Add arsenal in \(.applicationName)",
                "Create arsenal with \(.applicationName)",
                "New arsenal in \(.applicationName)"
            ],
            shortTitle: "Add Arsenal",
            systemImageName: "plus.circle"
        )
    }
    
    static var shortcutTileColor: ShortcutTileColor = .blue
}

