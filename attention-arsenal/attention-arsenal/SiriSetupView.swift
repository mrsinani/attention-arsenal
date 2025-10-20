import SwiftUI
import AppIntents

/// View to help users set up Siri shortcuts
struct SiriSetupView: View {
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
        }
        .padding()
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

