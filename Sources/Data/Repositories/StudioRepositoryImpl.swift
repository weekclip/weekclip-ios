import Foundation
import WeekclipShared

/// Concrete implementation of StudioRepository
public class StudioRepositoryImpl: StudioRepository {
  private let apiClient: StudioAPIClient
  private let sessionManager: SessionManager

  public init(
    apiClient: StudioAPIClient = StudioAPIClient(),
    sessionManager: SessionManager? = nil
  ) {
    self.apiClient = apiClient
    self.sessionManager = sessionManager ?? SessionManager()
  }

  public func fetchStudios(limit: Int, offset: Int) async throws -> [Studio] {
    // Ensure we have a valid token
    if let token = sessionManager.accessToken {
      apiClient.setAccessToken(token)
    }

    return try await apiClient.fetchStudios(limit: limit, offset: offset)
  }

  public func fetchMedia(
    studioId: String,
    limit: Int,
    lastId: String?
  ) async throws -> [StudioMedia] {
    // Ensure we have a valid token
    if let token = sessionManager.accessToken {
      apiClient.setAccessToken(token)
    }

    return try await apiClient.fetchMedia(
      studioId: studioId,
      limit: limit,
      lastId: lastId
    )
  }

  public func searchStudios(query: String, limit: Int) async throws -> [Studio] {
    // Ensure we have a valid token
    if let token = sessionManager.accessToken {
      apiClient.setAccessToken(token)
    }

    return try await apiClient.searchStudios(query: query, limit: limit)
  }
}
