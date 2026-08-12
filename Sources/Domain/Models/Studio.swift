import Foundation

/// Studio role enumeration
public enum StudioRole: String, Codable, CaseIterable {
  case admin = "admin"
  case member = "member"
  case viewer = "viewer"
}

/// Domain model for Studio
public struct Studio: Identifiable, Equatable, Codable {
  public let id: String
  public let name: String
  public let description: String?
  public let logoUrl: String?
  public let role: StudioRole
  public let mediaCount: Int
  public let createdAt: String?
  public let updatedAt: String?

  public init(
    id: String,
    name: String,
    description: String? = nil,
    logoUrl: String? = nil,
    role: StudioRole,
    mediaCount: Int = 0,
    createdAt: String? = nil,
    updatedAt: String? = nil
  ) {
    self.id = id
    self.name = name
    self.description = description
    self.logoUrl = logoUrl
    self.role = role
    self.mediaCount = mediaCount
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}
