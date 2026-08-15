import Foundation
import Observation
import WeekclipDomain
import WeekclipShared

/// Dashboard state holder.
///
/// The reference shape for every screen that follows (PRD-0008 Phase 5): one
/// observable state object, all work in a `Task`, no SwiftUI types in here.
///
/// `@Observable` rather than `ObservableObject` (ADR-0002): SwiftUI tracks the
/// individual properties a view actually reads, so a change to `isRefreshing`
/// does not invalidate a view that only reads `studios`. With
/// `@Published`/`objectWillChange` every view observing the object recomputes
/// regardless.
///
/// `@MainActor` on the type, not on individual methods. State a view reads must
/// be main-isolated, and annotating piecemeal is how you end up with the one
/// mutation that is not.
@MainActor
@Observable
public final class DashboardViewModel {
  /// Full-screen loader. Distinct from `isRefreshing` so a reload does not
  /// blank out the list that is already on screen.
  public private(set) var isLoading = true
  public private(set) var isRefreshing = false
  public private(set) var studios: [Studio] = []
  public private(set) var error: AppError?

  /// Distinguishes "no studios" from "not loaded yet", which look the same.
  public var isEmpty: Bool { !isLoading && error == nil && studios.isEmpty }

  private let getStudios: GetStudios

  public init(getStudios: GetStudios) {
    self.getStudios = getStudios
  }

  /// First load. Called from `.task`, which cancels it if the view goes away.
  public func load() async {
    await run(isRefresh: false)
  }

  /// Pull-to-refresh, and the error state's retry.
  public func refresh() async {
    await run(isRefresh: true)
  }

  private func run(isRefresh: Bool) async {
    isLoading = !isRefresh
    isRefreshing = isRefresh
    // Clear the previous error now: leaving it up while a retry is in flight
    // shows a failure and a spinner at the same time.
    error = nil

    let result = await getStudios()

    isLoading = false
    isRefreshing = false

    switch result {
    case .success(let studios):
      self.studios = studios
      self.error = nil
    case .failure(let error):
      // The already-loaded list stays on screen. Replacing real rows with an
      // error because a background reload failed is a regression the user did
      // not ask for.
      self.error = error
      AppLog.ui.error("dashboard load failed: \(String(describing: error), privacy: .public)")
    }
  }
}
