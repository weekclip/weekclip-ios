import Foundation
import WeekclipShared

/// Session manager for handling authentication state
@Observable
public final class SessionManager {
  public private(set) var currentUser: User?
  public private(set) var isLoading = false
  public private(set) var error: WeekclipError?
  public private(set) var accessToken: String?
  public private(set) var refreshToken: String?

  private let keychainStorage = KeychainStorage.shared
  private let authClient: SupabaseAuthClient

  public var isAuthenticated: Bool {
    accessToken != nil && currentUser != nil
  }

  public init(authClient: SupabaseAuthClient = SupabaseAuthClient()) {
    self.authClient = authClient
    self.accessToken = keychainStorage.getAccessToken()
    self.refreshToken = keychainStorage.getRefreshToken()
  }

  /// Sign in with Google ID token
  public func signInWithGoogle(idToken: String) async {
    isLoading = true
    error = nil

    do {
      let user = try await authClient.signInWithGoogle(idToken: idToken)

      // Save token if available from auth client
      if let token = authClient.accessToken {
        self.accessToken = token
        try keychainStorage.saveAccessToken(token)
      }
      if let token = authClient.refreshToken {
        self.refreshToken = token
        try keychainStorage.saveRefreshToken(token)
      }

      self.currentUser = user
      isLoading = false
      AppLogger.info("Successfully signed in user: \(user.email)")
    } catch let err as WeekclipError {
      error = err
      isLoading = false
      AppLogger.error("Google sign in failed", error: err)
    } catch {
      let weekclipError = WeekclipError.unknown(error)
      self.error = weekclipError
      isLoading = false
      AppLogger.error("Google sign in failed with unknown error", error: error)
    }
  }

  /// Sign out current user
  public func signOut() async {
    isLoading = true
    error = nil

    do {
      try await authClient.signOut()
      try keychainStorage.deleteAll()

      self.currentUser = nil
      self.accessToken = nil
      self.refreshToken = nil
      isLoading = false

      AppLogger.info("Successfully signed out")
    } catch let err as WeekclipError {
      error = err
      isLoading = false
      AppLogger.error("Sign out failed", error: err)
    } catch {
      let weekclipError = WeekclipError.unknown(error)
      self.error = weekclipError
      isLoading = false
      AppLogger.error("Sign out failed with unknown error", error: error)
    }
  }

  /// Refresh authentication session
  public func refreshSession() async {
    isLoading = true
    error = nil

    do {
      if let user = try await authClient.refreshSession() {
        self.currentUser = user

        // Update stored token if available
        if let token = authClient.accessToken {
          self.accessToken = token
          try keychainStorage.saveAccessToken(token)
        }
      }
      isLoading = false
    } catch let err as WeekclipError {
      error = err
      isLoading = false
      AppLogger.error("Session refresh failed", error: err)
    } catch {
      let weekclipError = WeekclipError.unknown(error)
      self.error = weekclipError
      isLoading = false
      AppLogger.error("Session refresh failed with unknown error", error: error)
    }
  }

  /// Restore session from stored credentials
  public func restoreSession() async {
    isLoading = true
    error = nil

    do {
      if let user = try await authClient.getCurrentUser() {
        self.currentUser = user
        if let token = authClient.accessToken {
          self.accessToken = token
        }
      }
      isLoading = false
    } catch let err as WeekclipError {
      error = err
      isLoading = false
      // Restoration failure is not fatal - user will need to sign in
      AppLogger.warning("Session restoration failed: \(err.errorDescription ?? "")")
    } catch {
      isLoading = false
      AppLogger.warning("Session restoration failed with unknown error: \(error.localizedDescription)")
    }
  }

  /// Clear error state
  public func clearError() {
    error = nil
  }
}
