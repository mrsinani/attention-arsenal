import Foundation
import MSAL
import SwiftUI

/// Manager for Microsoft/Outlook Sign-In authentication state
class OutlookAuthManager: ObservableObject {
    static let shared = OutlookAuthManager()
    
    @Published var isSignedIn: Bool = false
    @Published var userEmail: String?
    @Published var userName: String?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    // Microsoft App Registration values
    private let kClientID = "486320e4-4f4d-41ee-91ff-532f12e96fd5"
    private let kRedirectUri = "msauth.main.attention-arsenal://auth"
    private let kAuthority = "https://login.microsoftonline.com/common"
    
    // Scopes for Microsoft Graph API
    private let kScopes = ["User.Read", "Mail.Read"]
    
    private var applicationContext: MSALPublicClientApplication?
    private var currentAccount: MSALAccount?
    
    private init() {
        do {
            try initMSAL()
        } catch {
            print("Failed to initialize MSAL: \(error.localizedDescription)")
        }
    }
    
    /// Initialize MSAL application context
    private func initMSAL() throws {
        guard let authorityURL = URL(string: kAuthority) else {
            throw OutlookAuthError.invalidAuthority
        }
        
        let authority = try MSALAADAuthority(url: authorityURL)
        
        let msalConfiguration = MSALPublicClientApplicationConfig(
            clientId: kClientID,
            redirectUri: kRedirectUri,
            authority: authority
        )
        
        self.applicationContext = try MSALPublicClientApplication(configuration: msalConfiguration)
        
        // Configure logging globally (optional - for debugging)
        #if DEBUG
        MSALGlobalConfig.loggerConfig.logLevel = .warning
        #endif
    }
    
    /// Restore previous sign-in session if available
    @MainActor
    func restorePreviousSignIn() async {
        isLoading = true
        errorMessage = nil
        
        guard let applicationContext = applicationContext else {
            isLoading = false
            return
        }
        
        do {
            // Get all accounts from cache
            let accounts = try applicationContext.allAccounts()
            
            if let account = accounts.first {
                // Try to silently acquire token
                let parameters = MSALSilentTokenParameters(scopes: kScopes, account: account)
                let result = try await applicationContext.acquireTokenSilent(with: parameters)
                
                self.currentAccount = result.account
                self.userEmail = result.account.username
                self.userName = result.account.username
                self.isSignedIn = true
            }
        } catch {
            // Silent acquisition failed - user needs to sign in interactively
            print("No previous Outlook sign-in to restore: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
    
    /// Sign in with Microsoft
    @MainActor
    func signIn() async {
        isLoading = true
        errorMessage = nil
        
        guard let applicationContext = applicationContext else {
            errorMessage = "MSAL not initialized"
            isLoading = false
            return
        }
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            errorMessage = "Unable to find root view controller"
            isLoading = false
            return
        }
        
        let webViewParameters = MSALWebviewParameters(authPresentationViewController: rootViewController)
        let interactiveParameters = MSALInteractiveTokenParameters(scopes: kScopes, webviewParameters: webViewParameters)
        interactiveParameters.promptType = .selectAccount
        
        do {
            let result = try await applicationContext.acquireToken(with: interactiveParameters)
            
            self.currentAccount = result.account
            self.userEmail = result.account.username
            self.userName = result.account.username
            self.isSignedIn = true
            
        } catch let error as NSError {
            if error.domain == MSALErrorDomain {
                if error.code == MSALError.userCanceled.rawValue {
                    // User canceled - not an error
                    print("User canceled sign-in")
                } else {
                    errorMessage = "Sign-in failed: \(error.localizedDescription)"
                }
            } else {
                errorMessage = "Sign-in failed: \(error.localizedDescription)"
            }
        }
        
        isLoading = false
    }
    
    /// Sign out from Microsoft
    @MainActor
    func signOut() {
        guard let applicationContext = applicationContext,
              let account = currentAccount else {
            isSignedIn = false
            return
        }
        
        do {
            // Remove account from cache
            try applicationContext.remove(account)
        } catch {
            print("Failed to remove account: \(error.localizedDescription)")
        }
        
        currentAccount = nil
        isSignedIn = false
        userEmail = nil
        userName = nil
        errorMessage = nil
    }
    
    /// Get access token for API calls
    func getAccessToken() async throws -> String {
        guard let applicationContext = applicationContext else {
            throw OutlookAuthError.notInitialized
        }
        
        guard let account = currentAccount else {
            throw OutlookAuthError.notSignedIn
        }
        
        let parameters = MSALSilentTokenParameters(scopes: kScopes, account: account)
        
        do {
            let result = try await applicationContext.acquireTokenSilent(with: parameters)
            return result.accessToken
        } catch {
            // Token refresh failed - need to re-authenticate
            throw OutlookAuthError.tokenRefreshFailed
        }
    }
}

// MARK: - Errors

enum OutlookAuthError: LocalizedError {
    case invalidAuthority
    case notInitialized
    case notSignedIn
    case tokenRefreshFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidAuthority:
            return "Invalid authority URL"
        case .notInitialized:
            return "MSAL not initialized"
        case .notSignedIn:
            return "Not signed in to Microsoft"
        case .tokenRefreshFailed:
            return "Failed to refresh access token. Please sign in again."
        }
    }
}
