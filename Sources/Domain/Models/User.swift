import Foundation

/// Domain model for authenticated user
public struct User: Identifiable, Equatable {
  public let id: String
  public let email: String
  public let displayName: String?
  public let avatarUrl: String?

  public init(
    id: String,
    email: String,
    displayName: String? = nil,
    avatarUrl: String? = nil
  ) {
    self.id = id
    self.email = email
    self.displayName = displayName
    self.avatarUrl = avatarUrl
  }
}
