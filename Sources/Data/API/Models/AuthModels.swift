import Foundation

// MARK: - Request Models

/// Google Sign-In request
public struct GoogleSignInRequest: Encodable {
  let idToken: String
  let codeVerifier: String? // For PKCE flow

  enum CodingKeys: String, CodingKey {
    case idToken = "id_token"
    case codeVerifier = "code_verifier"
  }
}

// MARK: - Response Models

/// Authentication response
public struct AuthResponse: Decodable {
  let session: SessionData
  let user: UserResponse
}

/// Session data from auth response
public struct SessionData: Decodable {
  let accessToken: String
  let refreshToken: String?
  let expiresIn: Int?
  let expiresAt: Int?
  let tokenType: String?

  enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case refreshToken = "refresh_token"
    case expiresIn = "expires_in"
    case expiresAt = "expires_at"
    case tokenType = "token_type"
  }
}

/// User data from auth response
public struct UserResponse: Decodable {
  let id: String
  let email: String?
  let userMetadata: UserMetadata?
  let createdAt: String?
  let updatedAt: String?

  enum CodingKeys: String, CodingKey {
    case id
    case email
    case userMetadata = "user_metadata"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}

/// User metadata structure
public struct UserMetadata: Decodable {
  let displayName: String?
  let avatarUrl: String?

  enum CodingKeys: String, CodingKey {
    case displayName = "display_name"
    case avatarUrl = "avatar_url"
  }
}
