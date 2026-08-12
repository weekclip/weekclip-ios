import Foundation

/// Use case for fetching media from a studio
public protocol GetMediaUseCaseProtocol {
  func callAsFunction(studioId: String, limit: Int, lastId: String?) async throws -> [StudioMedia]
}

public struct GetMediaUseCase: GetMediaUseCaseProtocol {
  private let repository: StudioRepository

  public init(repository: StudioRepository) {
    self.repository = repository
  }

  public func callAsFunction(
    studioId: String,
    limit: Int = 20,
    lastId: String? = nil
  ) async throws -> [StudioMedia] {
    return try await repository.fetchMedia(
      studioId: studioId,
      limit: limit,
      lastId: lastId
    )
  }
}
