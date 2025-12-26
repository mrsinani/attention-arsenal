import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Help & Support")) {
                    NavigationLink(destination: SiriCommandsHelpView()) {
                        HStack {
                            Image(systemName: "mic.fill")
                                .foregroundColor(.blue)
                                .frame(width: 30)
                            Text("How to Setup Siri Commands")
                        }
                    }
                    
                    NavigationLink(destination: WidgetSetupHelpView()) {
                        HStack {
                            Image(systemName: "square.grid.2x2.fill")
                                .foregroundColor(.purple)
                                .frame(width: 30)
                            Text("How to Add Widgets")
                        }
                    }
                }
                
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.5")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct SiriCommandsHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Setting Up Siri Commands")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding(.bottom, 10)
                
                VStack(alignment: .leading, spacing: 15) {
                    Text("To use Siri with Attention Arsenal, you can say:")
                        .font(.body)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        ExampleCommandView(command: "Hey Siri, add an arsenal for my dentist appointment tomorrow")
                        ExampleCommandView(command: "Hey Siri, add an arsenal to call mom this weekend")
                        ExampleCommandView(command: "Hey Siri, add an arsenal for the project deadline next Friday")
                    }
                    .padding(.leading, 10)
                    
                    Divider()
                        .padding(.vertical, 10)
                    
                    Text("Setting Up Custom Shortcuts")
                        .font(.headline)
                        .padding(.top, 10)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        InstructionStep(number: 1, text: "Open the Shortcuts app")
                        InstructionStep(number: 2, text: "Tap the + icon to add a shortcut")
                        InstructionStep(number: 3, text: "Search for \"Attention Arsenal\" and tap it")
                        InstructionStep(number: 4, text: "Click \"Save\"")
                        InstructionStep(number: 5, text: "Rename the shortcut to your preferred phrase (e.g., \"add a reminder\")")
                    }
                    
                    Text("Siri will recognize that phrase and ask you what you would like to be reminded about.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                        .padding(.leading, 10)
                    
                    Divider()
                        .padding(.vertical, 10)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tips")
                            .font(.headline)
                        
                        TipView(icon: "lightbulb.fill", text: "You can include due dates in your command, or leave them out for flexible reminders")
                        TipView(icon: "sparkles", text: "The AI will automatically suggest appropriate notification intervals based on your request")
                        TipView(icon: "calendar", text: "Mention specific dates like \"tomorrow\", \"next week\", or \"January 15th\"")
                    }
                    .padding(.top, 5)
                }
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle("Siri Commands")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct WidgetSetupHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Adding Widgets to Home Screen")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding(.bottom, 10)
                
                VStack(alignment: .leading, spacing: 15) {
                    Text("Keep your arsenals visible on your Home Screen with widgets.")
                        .font(.body)
                    
                    Divider()
                        .padding(.vertical, 10)
                    
                    Text("How to Add a Widget")
                        .font(.headline)
                        .padding(.top, 5)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        InstructionStep(number: 1, text: "Touch and hold an empty area on your Home Screen until the apps start to jiggle")
                        InstructionStep(number: 2, text: "Tap the + button in the top left corner")
                        InstructionStep(number: 3, text: "Search for \"Attention Arsenal\" in the widget gallery")
                        InstructionStep(number: 4, text: "Tap on the Attention Arsenal widget")
                        InstructionStep(number: 5, text: "Swipe left or right to choose a widget size")
                        InstructionStep(number: 6, text: "Tap \"Add Widget\"")
                        InstructionStep(number: 7, text: "Drag the widget to your desired location")
                        InstructionStep(number: 8, text: "Tap \"Done\" in the top right corner")
                    }
                    
                    Divider()
                        .padding(.vertical, 10)
                    
                    Text("Widget Sizes")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        WidgetSizeInfo(size: "Small", description: "Shows your next upcoming arsenal at a glance")
                        WidgetSizeInfo(size: "Medium", description: "Displays up to 2 arsenals with descriptions and dates")
                    }
                    .padding(.leading, 10)
                    
                    Divider()
                        .padding(.vertical, 10)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tips")
                            .font(.headline)
                        
                        TipView(icon: "hand.tap.fill", text: "Tap the widget to open the app directly")
                        TipView(icon: "arrow.clockwise", text: "Widgets update automatically throughout the day")
                        TipView(icon: "square.stack.3d.up.fill", text: "You can stack widgets by dragging one on top of another")
                        TipView(icon: "minus.circle", text: "To remove a widget, long press it and tap \"Remove Widget\"")
                    }
                    .padding(.top, 5)
                }
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle("Add Widgets")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct WidgetSizeInfo: View {
    let size: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .foregroundColor(.purple)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(size)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct ExampleCommandView: View {
    let command: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "quote.opening")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 2)
            
            Text(command)
                .font(.body)
                .foregroundColor(.primary)
                .italic()
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct InstructionStep: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 24, height: 24)
                
                Text("\(number)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            
            Text(text)
                .font(.body)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

struct TipView: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.orange)
                .frame(width: 20)
            
            Text(text)
                .font(.callout)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    SettingsView()
}

#Preview("Siri Help") {
    NavigationView {
        SiriCommandsHelpView()
    }
}

#Preview("Widget Help") {
    NavigationView {
        WidgetSetupHelpView()
    }
}

