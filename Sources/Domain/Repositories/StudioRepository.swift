import Foundation

/// Repository protocol for studio operations
public protocol StudioRepository {
  /// Fetch paginated list of studios for current user
  /// - Parameters:
  ///   - limit: Number of studios to fetch (default: 10)
  ///   - offset: Pagination offset (default: 0)
  /// - Returns: List of studios
  func fetchStudios(limit: Int, offset: Int) async throws -> [Studio]

  /// Fetch paginated media list for a studio
  /// - Parameters:
  ///   - studioId: ID of the studio
  ///   - limit: Number of media items to fetch (default: 20)
  ///   - lastId: Cursor for pagination (fetch items after this ID)
  /// - Returns: List of media items
  func fetchMedia(studioId: String, limit: Int, lastId: String?) async throws -> [StudioMedia]

  /// Search studios by name
  /// - Parameters:
  ///   - query: Search query string
  ///   - limit: Number of results to fetch
  /// - Returns: List of matching studios
  func searchStudios(query: String, limit: Int) async throws -> [Studio]
}
