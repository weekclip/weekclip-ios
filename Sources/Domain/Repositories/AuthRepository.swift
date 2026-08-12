import Foundation

/// Repository protocol for authentication operations
public protocol AuthRepository {
  /// Sign in with Google using PKCE flow
  func signInWithGoogle(idToken: String) async throws -> User

  /// Sign out current user
  func signOut() async throws

  /// Get current authenticated user
  func getCurrentUser() async throws -> User?

  /// Refresh session
  func refreshSession() async throws -> User?

  /// Check if user is authenticated
  var isAuthenticated: Bool { get }

  /// Get stored access token
  var accessToken: String? { get }
}
