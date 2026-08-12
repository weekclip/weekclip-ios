import Foundation
import Supabase
import WeekclipShared

/// Supabase authentication client wrapper
public class SupabaseAuthClient {
  private let supabaseClient: SupabaseClient
  public private(set) var accessToken: String?
  public private(set) var refreshToken: String?

  public init(
    supabaseURL: URL = URL(string: "https://weekclip-supabase-url.supabase.co")!,
    supabaseKey: String = "your-supabase-anon-key"
  ) {
    self.supabaseClient = SupabaseClient(
      supabaseURL: supabaseURL,
      supabaseKey: supabaseKey
    )
  }

  /// Sign in with Google ID token using PKCE flow
  public func signInWithGoogle(idToken: String) async throws -> User {
    do {
      // Use Supabase's built-in Google sign-in
      let session = try await supabaseClient.auth.signIn(
        with: .idToken(
          credentials: IDTokenCredentials(
            provider: .google,
            idToken: idToken
          )
        )
      )

      // Store tokens
      self.accessToken = session.accessToken
      self.refreshToken = session.refreshToken

      return mapToUser(from: session.user)
    } catch {
      AppLogger.error("Supabase Google sign in failed", error: error)
      throw WeekclipError.unknown(error)
    }
  }

  /// Sign out
  public func signOut() async throws {
    do {
      try await supabaseClient.auth.signOut()
      self.accessToken = nil
      self.refreshToken = nil
    } catch {
      AppLogger.error("Supabase sign out failed", error: error)
      throw WeekclipError.unknown(error)
    }
  }

  /// Get current authenticated user
  public func getCurrentUser() async throws -> User? {
    do {
      if let authUser = try await supabaseClient.auth.session.user {
        // Update tokens if available
        if let session = try await supabaseClient.auth.session {
          self.accessToken = session.accessToken
          self.refreshToken = session.refreshToken
        }
        return mapToUser(from: authUser)
      }
      return nil
    } catch {
      AppLogger.error("Failed to get current user", error: error)
      throw WeekclipError.unknown(error)
    }
  }

  /// Refresh authentication session
  public func refreshSession() async throws -> User? {
    do {
      if let session = try await supabaseClient.auth.refreshSession() {
        self.accessToken = session.accessToken
        self.refreshToken = session.refreshToken
        return mapToUser(from: session.user)
      }
      return nil
    } catch {
      AppLogger.error("Failed to refresh session", error: error)
      throw WeekclipError.unknown(error)
    }
  }

  // MARK: - Private Helpers

  private func mapToUser(from authUser: AuthUser) -> User {
    let metadata = authUser.userMetadata ?? [:]
    let displayName = metadata["display_name"] as? String
      ?? metadata["name"] as? String
    let avatarUrl = metadata["avatar_url"] as? String

    return User(
      id: authUser.id.uuidString,
      email: authUser.email ?? "",
      displayName: displayName,
      avatarUrl: avatarUrl
    )
  }
}
