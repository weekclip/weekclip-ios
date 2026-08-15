import Foundation
import Observation
import WeekclipDomain
import WeekclipShared

/// Dashboard state holder.
///
/// The reference shape for every screen that follows (PRD-0008 Phase 5): one
/// observable `DashboardUiState`, all work in a `Task`, no SwiftUI types in here.
///
/// `@Observable` rather than `ObservableObject` (ADR-0002): SwiftUI tracks the
/// individual properties a view actually reads, so a change no view reads does
/// not invalidate anything. With `@Published`/`objectWillChange` every view
/// observing the object recomputes regardless.
///
/// `@MainActor` on the type, not on individual methods. State a view reads must
/// be main-isolated, and annotating piecemeal is how you end up with the one
/// mutation that is not.
@MainActor
@Observable
public final class DashboardViewModel {
  public private(set) var state = DashboardUiState()

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
    state.isLoading = !isRefresh
    state.isRefreshing = isRefresh
    // Clear the previous error now: leaving it up while a retry is in flight
    // shows a failure and a spinner at the same time.
    state.error = nil

    let result = await getStudios()

    state.isLoading = false
    state.isRefreshing = false

    switch result {
    case .success(let studios):
      state.studios = studios
      state.error = nil
    case .failure(let error):
      // The already-loaded list stays on screen. Replacing real rows with an
      // error because a background reload failed is a regression the user did
      // not ask for.
      state.error = error
      AppLog.ui.error("dashboard load failed: \(String(describing: error), privacy: .public)")
    }
  }
}
