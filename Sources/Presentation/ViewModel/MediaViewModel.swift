import Foundation
import SwiftUI

/// ViewModel for media operations using @Observable (iOS 17+)
@Observable
public class MediaViewModel {
  public var mediaList: [String] = []
  public var isLoading = false
  public var errorMessage: String?

  public init() {}

  @MainActor
  public func loadMedia() async {
    isLoading = true
    errorMessage = nil

    do {
      // Placeholder for actual API call
      try await Task.sleep(nanoseconds: 100_000_000) // Simulate delay
      mediaList = ["Media 1", "Media 2", "Media 3"]
      isLoading = false
    } catch {
      errorMessage = error.localizedDescription
      isLoading = false
    }
  }
}
