import Foundation

/// Service for interacting with the Gmail API
class GmailService {
    static let shared = GmailService()
    
    private let baseURL = "https://gmail.googleapis.com/gmail/v1/users/me"
    private let urlSession: URLSession
    
    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.urlSession = URLSession(configuration: configuration)
    }
    
    /// Fetch recent emails from Gmail
    /// - Parameter maxResults: Maximum number of emails to fetch (default: 100)
    /// - Returns: Array of EmailMessage objects
    func fetchEmails(maxResults: Int = 100) async throws -> [EmailMessage] {
        // Get access token
        let accessToken = try await GmailAuthManager.shared.getAccessToken()
        
        // First, get list of message IDs
        let messageIds = try await fetchMessageIds(accessToken: accessToken, maxResults: maxResults)
        
        // Then fetch details for each message
        var emails: [EmailMessage] = []
        
        // Fetch in batches to avoid overwhelming the API
        let batchSize = 10
        for batch in stride(from: 0, to: messageIds.count, by: batchSize) {
            let endIndex = min(batch + batchSize, messageIds.count)
            let batchIds = Array(messageIds[batch..<endIndex])
            
            // Fetch batch concurrently
            await withTaskGroup(of: EmailMessage?.self) { group in
                for messageId in batchIds {
                    group.addTask {
                        try? await self.fetchMessageDetails(messageId: messageId, accessToken: accessToken)
                    }
                }
                
                for await email in group {
                    if let email = email {
                        emails.append(email)
                    }
                }
            }
        }
        
        // Sort by date (newest first)
        return emails.sorted { $0.date > $1.date }
    }
    
    /// Fetch list of message IDs
    private func fetchMessageIds(accessToken: String, maxResults: Int) async throws -> [String] {
        var urlComponents = URLComponents(string: "\(baseURL)/messages")!
        urlComponents.queryItems = [
            URLQueryItem(name: "maxResults", value: String(maxResults)),
            URLQueryItem(name: "labelIds", value: "INBOX") // Only inbox messages
        ]
        
        guard let url = urlComponents.url else {
            throw GmailServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailServiceError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(GmailErrorResponse.self, from: data) {
                throw GmailServiceError.apiError(errorResponse.error.message)
            }
            throw GmailServiceError.httpError(httpResponse.statusCode)
        }
        
        let listResponse = try JSONDecoder().decode(MessageListResponse.self, from: data)
        return listResponse.messages?.map { $0.id } ?? []
    }
    
    /// Fetch details for a single message
    private func fetchMessageDetails(messageId: String, accessToken: String) async throws -> EmailMessage {
        var urlComponents = URLComponents(string: "\(baseURL)/messages/\(messageId)")!
        urlComponents.queryItems = [
            URLQueryItem(name: "format", value: "metadata"),
            URLQueryItem(name: "metadataHeaders", value: "Subject"),
            URLQueryItem(name: "metadataHeaders", value: "From"),
            URLQueryItem(name: "metadataHeaders", value: "Date")
        ]
        
        guard let url = urlComponents.url else {
            throw GmailServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GmailServiceError.invalidResponse
        }
        
        let messageResponse = try JSONDecoder().decode(MessageResponse.self, from: data)
        return parseMessage(messageResponse)
    }
    
    /// Parse Gmail API message response into EmailMessage
    private func parseMessage(_ response: MessageResponse) -> EmailMessage {
        var subject = "No Subject"
        var sender = "Unknown"
        var date = Date()
        
        // Extract headers
        if let headers = response.payload?.headers {
            for header in headers {
                switch header.name.lowercased() {
                case "subject":
                    subject = header.value
                case "from":
                    sender = parseFromHeader(header.value)
                case "date":
                    date = parseDate(header.value)
                default:
                    break
                }
            }
        }
        
        // Check if unread
        let isRead = !(response.labelIds?.contains("UNREAD") ?? false)
        
        return EmailMessage(
            id: response.id,
            subject: subject,
            sender: sender,
            body: response.snippet ?? "",
            date: date,
            isRead: isRead
        )
    }
    
    /// Parse the From header to extract just the name or email
    private func parseFromHeader(_ from: String) -> String {
        // Format could be: "Name <email@example.com>" or just "email@example.com"
        if let nameMatch = from.range(of: "^[^<]+", options: .regularExpression) {
            let name = String(from[nameMatch]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty && !name.contains("@") {
                return name
            }
        }
        
        // Extract email if no name
        if let emailMatch = from.range(of: "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+", options: .regularExpression) {
            return String(from[emailMatch])
        }
        
        return from
    }
    
    /// Parse date string from email header
    private func parseDate(_ dateString: String) -> Date {
        let formatters: [DateFormatter] = [
            {
                let f = DateFormatter()
                f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
                f.locale = Locale(identifier: "en_US_POSIX")
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "dd MMM yyyy HH:mm:ss Z"
                f.locale = Locale(identifier: "en_US_POSIX")
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
                f.locale = Locale(identifier: "en_US_POSIX")
                return f
            }()
        ]
        
        for formatter in formatters {
            if let date = formatter.date(from: dateString) {
                return date
            }
        }
        
        // Fallback to current date if parsing fails
        return Date()
    }
}

// MARK: - API Response Models

struct MessageListResponse: Codable {
    let messages: [MessageRef]?
    let nextPageToken: String?
    let resultSizeEstimate: Int?
    
    struct MessageRef: Codable {
        let id: String
        let threadId: String
    }
}

struct MessageResponse: Codable {
    let id: String
    let threadId: String
    let labelIds: [String]?
    let snippet: String?
    let payload: Payload?
    let internalDate: String?
    
    struct Payload: Codable {
        let headers: [Header]?
    }
    
    struct Header: Codable {
        let name: String
        let value: String
    }
}

struct GmailErrorResponse: Codable {
    let error: ErrorDetail
    
    struct ErrorDetail: Codable {
        let code: Int
        let message: String
        let status: String?
    }
}

// MARK: - Errors

enum GmailServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case noMessages
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from Gmail API"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return "Gmail API error: \(message)"
        case .noMessages:
            return "No messages found"
        }
    }
}
