import Foundation

/// Service for interacting with OpenAI's Chat Completion API
class OpenAIService {
    static let shared = OpenAIService()
    
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    private let urlSession: URLSession
    
    private init() {
        self.apiKey = Secrets.openAIAPIKey
        
        // Configure URLSession with proper settings
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.urlSession = URLSession(configuration: configuration)
        
        // Validate API key
        if apiKey == "YOUR_OPENAI_API_KEY_HERE" || apiKey.isEmpty {
            print("⚠️ WARNING: OpenAI API key not configured. Please add your key to Secrets.swift")
        }
    }
    
    /// Send a chat completion request to OpenAI
    /// - Parameters:
    ///   - messages: Array of chat messages
    ///   - model: The model to use (default: gpt-4o-mini for cost efficiency)
    ///   - temperature: Sampling temperature (0-2)
    ///   - maxTokens: Maximum tokens in response
    /// - Returns: The assistant's response text
    func sendChatCompletion(
        messages: [ChatMessage],
        model: String = "gpt-4o-mini",
        temperature: Double = 0.7,
        maxTokens: Int = 500
    ) async throws -> String {
        
        // Validate API key
        guard apiKey != "YOUR_OPENAI_API_KEY_HERE" && !apiKey.isEmpty else {
            throw OpenAIError.missingAPIKey
        }
        
        // Create request
        guard let url = URL(string: baseURL) else {
            throw OpenAIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Create request body
        let requestBody = ChatCompletionRequest(
            model: model,
            messages: messages,
            temperature: temperature,
            max_tokens: maxTokens
        )
        
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        // Send request
        let (data, response) = try await urlSession.data(for: request)
        
        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            // Try to decode error message
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                throw OpenAIError.apiError(errorResponse.error.message)
            }
            throw OpenAIError.httpError(httpResponse.statusCode)
        }
        
        // Decode response
        let completionResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        
        guard let firstChoice = completionResponse.choices.first else {
            throw OpenAIError.noResponse
        }
        
        return firstChoice.message.content
    }
    
    /// Convenience method to send a simple text prompt
    /// - Parameter prompt: The user's message/question
    /// - Returns: The assistant's response text
    func sendPrompt(_ prompt: String) async throws -> String {
        let messages = [ChatMessage(role: "user", content: prompt)]
        return try await sendChatCompletion(messages: messages)
    }
}

// MARK: - Models

struct ChatMessage: Codable {
    let role: String  // "system", "user", or "assistant"
    let content: String
}

struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let max_tokens: Int
}

struct ChatCompletionResponse: Codable {
    let id: String
    let choices: [Choice]
    let usage: Usage
    
    struct Choice: Codable {
        let index: Int
        let message: ChatMessage
        let finish_reason: String
    }
    
    struct Usage: Codable {
        let prompt_tokens: Int
        let completion_tokens: Int
        let total_tokens: Int
    }
}

struct OpenAIErrorResponse: Codable {
    let error: ErrorDetail
    
    struct ErrorDetail: Codable {
        let message: String
        let type: String
        let code: String?
    }
}

// MARK: - Errors

enum OpenAIError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case noResponse
    
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key is not configured. Please add your key to Secrets.swift"
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from OpenAI API"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return "OpenAI API error: \(message)"
        case .noResponse:
            return "No response from OpenAI API"
        }
    }
}

// MARK: - Example Usage
/*
 Usage examples:
 
 // Simple prompt
 Task {
     do {
         let response = try await OpenAIService.shared.sendPrompt("What is the capital of France?")
         print(response)
     } catch {
         print("Error: \(error.localizedDescription)")
     }
 }
 
 // With conversation context
 Task {
     let messages = [
         ChatMessage(role: "system", content: "You are a helpful assistant."),
         ChatMessage(role: "user", content: "Help me brainstorm task ideas.")
     ]
     
     do {
         let response = try await OpenAIService.shared.sendChatCompletion(messages: messages)
         print(response)
     } catch {
         print("Error: \(error.localizedDescription)")
     }
 }
*/

