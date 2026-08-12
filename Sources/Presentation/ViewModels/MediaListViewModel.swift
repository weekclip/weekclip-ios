import Foundation
import SwiftUI
import WeekclipShared

/// ViewModel for media list with cursor-based pagination
@Observable
public final class MediaListViewModel {
  public let studioId: String
  public private(set) var mediaList: [StudioMedia] = []
  public private(set) var isLoading = false
  public private(set) var isLoadingMore = false
  public private(set) var error: WeekclipError?
  public private(set) var hasMore = false

  private let repository: StudioRepository
  private var nextCursor: String? = nil

  public init(
    studioId: String,
    repository: StudioRepository? = nil
  ) {
    self.studioId = studioId
    self.repository = repository ?? StudioRepositoryImpl()
  }

  /// Initial load of media list
  @MainActor
  public func loadMedia() async {
    isLoading = true
    error = nil
    nextCursor = nil

    do {
      let media = try await repository.fetchMedia(
        studioId: studioId,
        limit: 20,
        lastId: nil
      )
      self.mediaList = media
      self.hasMore = media.count >= 20 // Simplified check
      self.isLoading = false

      AppLogger.info("Loaded \(media.count) media items for studio: \(studioId)")
    } catch let err as WeekclipError {
      self.error = err
      self.isLoading = false
      AppLogger.error("Failed to load media", error: err)
    } catch {
      let weekclipError = WeekclipError.unknown(error)
      self.error = weekclipError
      self.isLoading = false
      AppLogger.error("Failed to load media", error: error)
    }
  }

  /// Load more media items (pagination)
  @MainActor
  public func loadMore() async {
    guard !isLoadingMore && hasMore, let lastMediaId = mediaList.last?.id else {
      return
    }

    isLoadingMore = true
    error = nil

    do {
      let moreMedia = try await repository.fetchMedia(
        studioId: studioId,
        limit: 20,
        lastId: lastMediaId
      )

      self.mediaList.append(contentsOf: moreMedia)
      self.hasMore = moreMedia.count >= 20

      self.isLoadingMore = false

      AppLogger.info("Loaded \(moreMedia.count) more media items")
    } catch let err as WeekclipError {
      self.error = err
      self.isLoadingMore = false
      AppLogger.error("Failed to load more media", error: err)
    } catch {
      let weekclipError = WeekclipError.unknown(error)
      self.error = weekclipError
      self.isLoadingMore = false
      AppLogger.error("Failed to load more media", error: error)
    }
  }

  /// Refresh media list
  @MainActor
  public func refresh() async {
    await loadMedia()
  }

  /// Clear error state
  public func clearError() {
    error = nil
  }
}
