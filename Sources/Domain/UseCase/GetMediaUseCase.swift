import Foundation

/// Use case for fetching media
public protocol GetMediaUseCaseProtocol {
  func callAsFunction() async throws -> [Media]
}

public struct GetMediaUseCase: GetMediaUseCaseProtocol {
  public init() {}

  public func callAsFunction() async throws -> [Media] {
    // Placeholder
    return []
  }
}

/// Media model
public struct Media: Identifiable, Codable {
  public let id: String
  public let title: String
  public let url: String

  public init(id: String, title: String, url: String) {
    self.id = id
    self.title = title
    self.url = url
  }
}
