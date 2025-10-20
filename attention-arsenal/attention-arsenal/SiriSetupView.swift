import SwiftUI
import AppIntents

/// View to help users set up Siri shortcuts
struct SiriSetupView: View {
    @State private var showingSettings = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            VStack(spacing: 12) {
                Text("Voice Commands")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Add arsenals with Siri")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                Text("Say:")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 12) {
                    ExamplePhrase(text: "\"Hey Siri, add arsenal in Attention Arsenal\"")
                    ExamplePhrase(text: "\"Hey Siri, create arsenal with Attention Arsenal\"")
                }
                .padding(.leading, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)
            
            VStack(spacing: 12) {
                Text("Want a shorter phrase?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Button(action: {
                    openSiriSettings()
                }) {
                    HStack {
                        Image(systemName: "gear")
                        Text("Set Up Custom Phrase")
                    }
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                }
            }
            
            Text("You can customize \"Hey Siri, add an arsenal\" to work with this app")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
    
    private func openSiriSettings() {
        // Open Settings to Siri & Search
        if let url = URL(string: "App-prefs:SIRI") {
            UIApplication.shared.open(url)
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

struct ExamplePhrase: View {
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "quote.bubble")
                .font(.caption)
                .foregroundColor(.blue)
            
            Text(text)
                .font(.body)
                .foregroundColor(.primary)
        }
    }
}

#Preview {
    SiriSetupView()
}

