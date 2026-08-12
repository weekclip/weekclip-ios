import Foundation
import SwiftUI
import WeekclipShared

/// ViewModel for studio list operations
@Observable
public final class StudioListViewModel {
  public private(set) var studios: [Studio] = []
  public private(set) var filteredStudios: [Studio] = []
  public private(set) var isLoading = false
  public private(set) var isSearching = false
  public private(set) var error: WeekclipError?

  public var searchText = "" {
    didSet {
      performSearch()
    }
  }

  private let repository: StudioRepository
  private var allStudios: [Studio] = []

  public init(repository: StudioRepository? = nil) {
    self.repository = repository ?? StudioRepositoryImpl()
  }

  /// Load studios for current user
  @MainActor
  public func loadStudios() async {
    isLoading = true
    error = nil

    do {
      let loadedStudios = try await repository.fetchStudios(limit: 100, offset: 0)
      self.studios = loadedStudios
      self.allStudios = loadedStudios
      self.filteredStudios = loadedStudios
      self.isLoading = false

      AppLogger.info("Loaded \(loadedStudios.count) studios")
    } catch let err as WeekclipError {
      self.error = err
      self.isLoading = false
      AppLogger.error("Failed to load studios", error: err)
    } catch {
      let weekclipError = WeekclipError.unknown(error)
      self.error = weekclipError
      self.isLoading = false
      AppLogger.error("Failed to load studios", error: error)
    }
  }

  /// Perform search on studios
  private func performSearch() {
    if searchText.isEmpty {
      filteredStudios = studios
      isSearching = false
      return
    }

    isSearching = true

    // Local filtering first
    let query = searchText.lowercased()
    filteredStudios = studios.filter { studio in
      studio.name.lowercased().contains(query) ||
      (studio.description?.lowercased().contains(query) ?? false)
    }
  }

  /// Refresh studios
  @MainActor
  public func refresh() async {
    await loadStudios()
  }

  /// Clear error state
  public func clearError() {
    error = nil
  }
}
