import Foundation

/// Service for interacting with Microsoft Graph API to fetch Outlook emails
class OutlookService {
    static let shared = OutlookService()
    
    private let graphEndpoint = "https://graph.microsoft.com/v1.0"
    private let urlSession: URLSession
    
    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.urlSession = URLSession(configuration: configuration)
    }
    
    /// Fetch recent emails from Outlook/Microsoft Graph
    /// - Parameter maxResults: Maximum number of emails to fetch (default: 100)
    /// - Returns: Array of EmailMessage objects
    func fetchEmails(maxResults: Int = 100) async throws -> [EmailMessage] {
        // Get access token
        let accessToken = try await OutlookAuthManager.shared.getAccessToken()
        
        // Build the request URL with query parameters
        var urlComponents = URLComponents(string: "\(graphEndpoint)/me/messages")!
        urlComponents.queryItems = [
            URLQueryItem(name: "$top", value: String(maxResults)),
            URLQueryItem(name: "$orderby", value: "receivedDateTime desc"),
            URLQueryItem(name: "$select", value: "id,subject,from,receivedDateTime,isRead,bodyPreview")
        ]
        
        guard let url = urlComponents.url else {
            throw OutlookServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OutlookServiceError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(GraphErrorResponse.self, from: data) {
                throw OutlookServiceError.apiError(errorResponse.error.message)
            }
            throw OutlookServiceError.httpError(httpResponse.statusCode)
        }
        
        let messagesResponse = try JSONDecoder().decode(MessagesResponse.self, from: data)
        
        return messagesResponse.value.map { message in
            EmailMessage(
                id: message.id,
                subject: message.subject ?? "No Subject",
                sender: parseSender(message.from),
                body: message.bodyPreview ?? "",
                date: parseDate(message.receivedDateTime),
                isRead: message.isRead ?? true
            )
        }
    }
    
    /// Parse sender information from Graph API response
    private func parseSender(_ from: MessageFrom?) -> String {
        guard let from = from,
              let emailAddress = from.emailAddress else {
            return "Unknown"
        }
        
        // Prefer display name, fall back to email address
        if let name = emailAddress.name, !name.isEmpty {
            return name
        }
        return emailAddress.address ?? "Unknown"
    }
    
    /// Parse ISO 8601 date string
    private func parseDate(_ dateString: String?) -> Date {
        guard let dateString = dateString else {
            return Date()
        }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: dateString) {
            return date
        }
        
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: dateString) {
            return date
        }
        
        return Date()
    }
}

// MARK: - Microsoft Graph API Response Models

struct MessagesResponse: Codable {
    let value: [GraphMessage]
    
    enum CodingKeys: String, CodingKey {
        case value
    }
}

struct GraphMessage: Codable {
    let id: String
    let subject: String?
    let from: MessageFrom?
    let receivedDateTime: String?
    let isRead: Bool?
    let bodyPreview: String?
}

struct MessageFrom: Codable {
    let emailAddress: EmailAddress?
}

struct EmailAddress: Codable {
    let name: String?
    let address: String?
}

struct GraphErrorResponse: Codable {
    let error: GraphError
}

struct GraphError: Codable {
    let code: String
    let message: String
}

// MARK: - Errors

enum OutlookServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from Microsoft Graph API"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return "Microsoft Graph API error: \(message)"
        }
    }
}
