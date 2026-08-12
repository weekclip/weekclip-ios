import Foundation

// MARK: - API Response Models

/// Studio list response
public struct StudioListResponse: Decodable {
  public let studios: [StudioResponse]
  public let totalCount: Int?
  public let hasMore: Bool?

  enum CodingKeys: String, CodingKey {
    case studios
    case totalCount = "total_count"
    case hasMore = "has_more"
  }
}

/// Individual studio response
public struct StudioResponse: Decodable {
  public let id: String
  public let name: String
  public let description: String?
  public let logoUrl: String?
  public let role: String
  public let mediaCount: Int?
  public let createdAt: String?
  public let updatedAt: String?

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case description
    case logoUrl = "logo_url"
    case role
    case mediaCount = "media_count"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}

// MARK: - Media Response Models

/// Media list response
public struct MediaListResponse: Decodable {
  public let media: [MediaResponse]
  public let hasMore: Bool?
  public let lastId: String?

  enum CodingKeys: String, CodingKey {
    case media
    case hasMore = "has_more"
    case lastId = "last_id"
  }
}

/// Preview response for media streaming
public struct PreviewResponse: Decodable {
  public let status: String
  public let manifestUrl: String?

  enum CodingKeys: String, CodingKey {
    case status
    case manifestUrl = "manifest_url"
  }
}

/// Individual media response
public struct MediaResponse: Decodable {
  public let id: String
  public let title: String
  public let description: String?
  public let studioId: String
  public let thumbnailUrl: String?
  public let duration: Int?
  public let status: String
  public let fileSize: Int?
  public let createdAt: String?
  public let updatedAt: String?
  public let preview: PreviewResponse?

  enum CodingKeys: String, CodingKey {
    case id
    case title
    case description
    case studioId = "studio_id"
    case thumbnailUrl = "thumbnail_url"
    case duration
    case status
    case fileSize = "file_size"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case preview
  }
}
