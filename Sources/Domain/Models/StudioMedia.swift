import Foundation

/// Media status enumeration
public enum MediaStatus: String, Codable, CaseIterable {
  case processing = "processing"
  case ready = "ready"
  case failed = "failed"
  case archived = "archived"
}

/// Preview information for media streaming
public struct MediaPreview: Equatable, Codable {
  public let status: String // "Ready" | "Processing" | "Missing"
  public let manifestUrl: String? // HLS manifest URL

  public init(
    status: String = "Missing",
    manifestUrl: String? = nil
  ) {
    self.status = status
    self.manifestUrl = manifestUrl
  }

  enum CodingKeys: String, CodingKey {
    case status
    case manifestUrl = "manifest_url"
  }
}

/// Domain model for media in a studio
public struct StudioMedia: Identifiable, Equatable, Codable {
  public let id: String
  public let title: String
  public let description: String?
  public let studioId: String
  public let thumbnailUrl: String?
  public let duration: Int? // in seconds
  public let status: MediaStatus
  public let fileSize: Int? // in bytes
  public let createdAt: String?
  public let updatedAt: String?
  public let preview: MediaPreview // HLS streaming info

  public init(
    id: String,
    title: String,
    description: String? = nil,
    studioId: String,
    thumbnailUrl: String? = nil,
    duration: Int? = nil,
    status: MediaStatus = .processing,
    fileSize: Int? = nil,
    createdAt: String? = nil,
    updatedAt: String? = nil,
    preview: MediaPreview = MediaPreview()
  ) {
    self.id = id
    self.title = title
    self.description = description
    self.studioId = studioId
    self.thumbnailUrl = thumbnailUrl
    self.duration = duration
    self.status = status
    self.fileSize = fileSize
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.preview = preview
  }

  /// Display duration in human readable format
  public var durationDisplay: String {
    guard let duration = duration else { return "--:--" }
    let minutes = duration / 60
    let seconds = duration % 60
    return String(format: "%02d:%02d", minutes, seconds)
  }

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
