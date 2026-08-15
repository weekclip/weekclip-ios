import Testing
import WeekclipDomain
import WeekclipShared

@testable import WeekclipPresentation

/// The screen's derived rules, as pure values.
///
/// These were originally asserted by catching the view model mid-flight with
/// `Task.yield()`. That test passed on one run and failed on the next: whether a
/// child task finishes on a single yield is a scheduling detail, not a fact
/// about the code. A flaky test is worse than no test, because the first thing
/// it teaches is to re-run it.
///
/// A Maestro flow was also tried for the retry case, on a real device. It
/// **could not fail on the buggy build** — with no network the request fails
/// instantly, so the wrong frame was gone before the assertion ran. A check that
/// cannot fail is not a check. This file is where the rule is actually pinned.
@Suite("DashboardUiState")
struct DashboardUiStateTests {

  private func studio(_ id: String) -> Studio {
    Studio(id: id, slug: id, name: id, ownerId: "owner", role: .owner)
  }

  @Test("the initial state is loading, and is not yet 'empty'")
  func initialState() {
    let state = DashboardUiState()

    #expect(state.showFullScreenLoader)
    #expect(!state.isEmpty, "'no studios' and 'not loaded yet' must not look the same")
  }

  @Test("retrying with nothing on screen shows the loader, never the empty state")
  func retryWithNoRows() {
    // What `refresh()` produces from the error state: error cleared, not
    // loading, refreshing, no rows. Before the fix this fell through to
    // `isEmpty` and the screen flashed "No studios yet" — found by tapping
    // retry on a real device (2026-08-15).
    let state = DashboardUiState(isLoading: false, isRefreshing: true, studios: [], error: nil)

    #expect(state.showFullScreenLoader)
    #expect(!state.isEmpty, "a retry must never claim the account has no studios")
  }

  @Test("refreshing with rows on screen keeps them instead of covering them")
  func refreshWithRows() {
    let state = DashboardUiState(isLoading: false, isRefreshing: true, studios: [studio("1")])

    #expect(!state.showFullScreenLoader, "rows are on screen — do not cover them")
    #expect(!state.isEmpty)
  }

  @Test("a settled load with no studios is the empty state")
  func settledEmpty() {
    let state = DashboardUiState(isLoading: false, isRefreshing: false, studios: [])

    #expect(!state.showFullScreenLoader)
    #expect(state.isEmpty)
  }

  @Test("an error is never also the empty state")
  func errorIsNotEmpty() {
    let state = DashboardUiState(
      isLoading: false, isRefreshing: false, studios: [], error: .offline)

    #expect(!state.isEmpty)
    #expect(!state.showFullScreenLoader)
  }
}
