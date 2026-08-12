import Foundation
import SwiftUI
import WeekclipShared

/// ViewModel for authentication operations
@Observable
public final class AuthViewModel {
  public private(set) var isAuthenticated = false
  public private(set) var isLoading = false
  public private(set) var error: WeekclipError?

  public var user: User? {
    sessionManager.currentUser
  }

  private let sessionManager: SessionManager
  private let authRepository: AuthRepository

  public init(
    sessionManager: SessionManager = SessionManager(),
    authRepository: AuthRepository? = nil
  ) {
    self.sessionManager = sessionManager
    self.authRepository = authRepository ?? AuthRepositoryImpl()

    // Sync auth state
    self.isAuthenticated = sessionManager.isAuthenticated
  }

  /// Sign in with Google ID token
  @MainActor
  public func signInWithGoogle(idToken: String) async {
    isLoading = true
    error = nil

    do {
      let user = try await authRepository.signInWithGoogle(idToken: idToken)
      sessionManager.currentUser = user
      sessionManager.accessToken = authRepository.accessToken

      self.isAuthenticated = true
      self.isLoading = false

      AppLogger.info("Successfully signed in user: \(user.email)")
    } catch let err as WeekclipError {
      self.error = err
      self.isLoading = false
      AppLogger.error("Google sign in failed", error: err)
    } catch {
      let weekclipError = WeekclipError.unknown(error)
      self.error = weekclipError
      self.isLoading = false
      AppLogger.error("Google sign in failed", error: error)
    }
  }

  /// Sign out
  @MainActor
  public func signOut() async {
    isLoading = true
    error = nil

    do {
      try await authRepository.signOut()
      sessionManager.currentUser = nil
      sessionManager.accessToken = nil

      self.isAuthenticated = false
      self.isLoading = false

      AppLogger.info("Successfully signed out")
    } catch let err as WeekclipError {
      self.error = err
      self.isLoading = false
      AppLogger.error("Sign out failed", error: err)
    } catch {
      let weekclipError = WeekclipError.unknown(error)
      self.error = weekclipError
      self.isLoading = false
      AppLogger.error("Sign out failed", error: error)
    }
  }

  /// Restore session from stored credentials
  @MainActor
  public func restoreSession() async {
    await sessionManager.restoreSession()
    self.isAuthenticated = sessionManager.isAuthenticated
  }

  /// Clear error state
  public func clearError() {
    error = nil
  }
}
