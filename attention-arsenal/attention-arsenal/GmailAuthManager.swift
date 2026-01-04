import Foundation
import GoogleSignIn
import SwiftUI

/// Manager for Google Sign-In authentication state
class GmailAuthManager: ObservableObject {
    static let shared = GmailAuthManager()
    
    @Published var isSignedIn: Bool = false
    @Published var userEmail: String?
    @Published var userName: String?
    @Published var userProfileURL: URL?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    /// The Gmail readonly scope for accessing emails
    private let gmailReadOnlyScope = "https://www.googleapis.com/auth/gmail.readonly"
    
    private init() {
        // Check initial state
        updateSignInState()
    }
    
    /// Update the sign-in state based on current Google Sign-In user
    private func updateSignInState() {
        if let user = GIDSignIn.sharedInstance.currentUser {
            isSignedIn = true
            userEmail = user.profile?.email
            userName = user.profile?.name
            userProfileURL = user.profile?.imageURL(withDimension: 100)
        } else {
            isSignedIn = false
            userEmail = nil
            userName = nil
            userProfileURL = nil
        }
    }
    
    /// Restore previous sign-in session if available
    @MainActor
    func restorePreviousSignIn() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            
            // Check if we have the Gmail scope, if not we need to re-authenticate
            if let user = GIDSignIn.sharedInstance.currentUser {
                let grantedScopes = user.grantedScopes ?? []
                if !grantedScopes.contains(gmailReadOnlyScope) {
                    // Need to request additional scope
                    print("Gmail scope not granted, will need to re-authenticate")
                    isSignedIn = false
                } else {
                    updateSignInState()
                }
            }
        } catch {
            // No previous sign-in or it failed - this is normal for first-time users
            print("No previous sign-in to restore: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
    
    /// Sign in with Google and request Gmail access
    @MainActor
    func signIn() async {
        isLoading = true
        errorMessage = nil
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            errorMessage = "Unable to find root view controller"
            isLoading = false
            return
        }
        
        do {
            // Sign in with Gmail scope
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: rootViewController,
                hint: nil,
                additionalScopes: [gmailReadOnlyScope]
            )
            
            // Verify we got the Gmail scope
            let grantedScopes = result.user.grantedScopes ?? []
            if grantedScopes.contains(gmailReadOnlyScope) {
                updateSignInState()
            } else {
                errorMessage = "Gmail access was not granted. Please try again and allow email access."
                isSignedIn = false
            }
        } catch let error as GIDSignInError {
            switch error.code {
            case .canceled:
                // User canceled - not really an error
                print("User canceled sign-in")
            case .hasNoAuthInKeychain:
                errorMessage = "No saved credentials found. Please sign in."
            default:
                errorMessage = "Sign-in failed: \(error.localizedDescription)"
            }
        } catch {
            errorMessage = "Sign-in failed: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    /// Sign out from Google
    @MainActor
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        isSignedIn = false
        userEmail = nil
        userName = nil
        userProfileURL = nil
        errorMessage = nil
    }
    
    /// Get the current access token for API calls
    /// This will automatically refresh the token if needed
    func getAccessToken() async throws -> String {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw GmailAuthError.notSignedIn
        }
        
        // Refresh tokens if needed
        try await user.refreshTokensIfNeeded()
        
        guard let accessToken = user.accessToken.tokenString as String? else {
            throw GmailAuthError.noAccessToken
        }
        
        return accessToken
    }
}

// MARK: - Errors

enum GmailAuthError: LocalizedError {
    case notSignedIn
    case noAccessToken
    case scopeNotGranted
    
    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Not signed in to Google"
        case .noAccessToken:
            return "Unable to get access token"
        case .scopeNotGranted:
            return "Gmail access was not granted"
        }
    }
}
