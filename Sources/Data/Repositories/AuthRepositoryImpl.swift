import Foundation
import WeekclipShared

/// Concrete implementation of AuthRepository
public class AuthRepositoryImpl: AuthRepository {
  private let authClient: SupabaseAuthClient
  private let keychainStorage = KeychainStorage.shared

  public init(authClient: SupabaseAuthClient = SupabaseAuthClient()) {
    self.authClient = authClient
  }

  public func signInWithGoogle(idToken: String) async throws -> User {
    let user = try await authClient.signInWithGoogle(idToken: idToken)

    // Store tokens
    if let token = authClient.accessToken {
      try keychainStorage.saveAccessToken(token)
    }
    if let token = authClient.refreshToken {
      try keychainStorage.saveRefreshToken(token)
    }

    return user
  }

  public func signOut() async throws {
    try await authClient.signOut()
    try keychainStorage.deleteAll()
  }

  public func getCurrentUser() async throws -> User? {
    return try await authClient.getCurrentUser()
  }

  public func refreshSession() async throws -> User? {
    return try await authClient.refreshSession()
  }

  public var isAuthenticated: Bool {
    accessToken != nil
  }

  public var accessToken: String? {
    authClient.accessToken
  }
}
