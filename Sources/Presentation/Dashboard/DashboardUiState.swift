import WeekclipDomain
import WeekclipShared

/// The whole screen in one value.
///
/// One struct rather than four independent properties, mirroring
/// `DashboardUiState` in weekclip-android. The states are not independent —
/// "loading" and "error" are mutually exclusive — and separate properties let a
/// view read a combination that never legally exists.
///
/// It is also what makes the derived rules below testable without concurrency.
/// They were originally computed properties on the view model, and the only way
/// to test them was to catch the view model mid-flight with `Task.yield()`;
/// that test passed once and failed the next run, because whether a child task
/// completes on one yield is a scheduling detail. A pure value has no such
/// problem.
public struct DashboardUiState: Equatable, Sendable {
  /// Full-screen loader. Distinct from `isRefreshing` so a reload does not blank
  /// out the list that is already on screen.
  public var isLoading: Bool
  public var isRefreshing: Bool
  public var studios: [Studio]
  public var error: AppError?

  public init(
    isLoading: Bool = true,
    isRefreshing: Bool = false,
    studios: [Studio] = [],
    error: AppError? = nil
  ) {
    self.isLoading = isLoading
    self.isRefreshing = isRefreshing
    self.studios = studios
    self.error = error
  }

  /// Whether to cover the screen with a loader.
  ///
  /// True while refreshing *if there is nothing to keep on screen*. Found by
  /// driving the Android twin on a real device (2026-08-15), and this code had
  /// the same shape: tapping retry from the error state clears the error, and
  /// with no rows loaded the view fell through to `isEmpty` and flashed
  /// "No studios yet" before the error came back. A retry that briefly claims
  /// the account has no studios is worse than a spinner.
  ///
  /// A refresh *with* rows still shows the rows — the whole reason
  /// `isRefreshing` is separate from `isLoading`.
  ///
  /// A Maestro flow was tried for this on the Android side and **could not fail
  /// on the buggy build**: with no network the request fails instantly, so the
  /// wrong frame is gone before the assertion runs. A check that cannot fail is
  /// not a check — which is why the pin is here, in a value test.
  public var showFullScreenLoader: Bool {
    isLoading || (isRefreshing && studios.isEmpty)
  }

  /// Distinguishes "no studios" from "not loaded yet", which look the same.
  public var isEmpty: Bool {
    !showFullScreenLoader && error == nil && studios.isEmpty
  }
}
