import Foundation
import Testing
import WeekclipDomain
import WeekclipShared

@testable import WeekclipPresentation

/// State transitions, driven by a stub repository.
///
/// A stub and not the URLProtocol harness: what is under test is the sequence
/// of states the screen sees, and routing that through the request pipeline
/// would make the test able to fail for reasons that have nothing to do with
/// the view model. The wire format is covered by
/// `StudioRepositoryContractTests`.
@Suite("DashboardViewModel")
@MainActor
struct DashboardViewModelTests {

  private final class StubRepository: StudioRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var _response: Result<[Studio], AppError>
    private var _callCount = 0

    init(_ response: Result<[Studio], AppError>) {
      self._response = response
    }

    var response: Result<[Studio], AppError> {
      get { lock.withLock { _response } }
      set { lock.withLock { _response = newValue } }
    }

    var callCount: Int { lock.withLock { _callCount } }

    func getStudios() async -> Result<[Studio], AppError> {
      lock.withLock { _callCount += 1 }
      return response
    }
  }

  private func studio(_ id: String, _ name: String, updatedAt: String? = nil) -> Studio {
    Studio(id: id, slug: id, name: name, ownerId: "owner", role: .owner, updatedAt: updatedAt)
  }

  private func makeViewModel(_ repository: StubRepository) -> DashboardViewModel {
    DashboardViewModel(getStudios: GetStudios(repository: repository))
  }

  @Test("starts loading so the screen never flashes an empty list")
  func startsLoading() {
    let viewModel = makeViewModel(StubRepository(.success([])))

    #expect(viewModel.isLoading)
    #expect(viewModel.studios.isEmpty)
    // Not empty yet — "no studios" and "not loaded" must not look the same.
    #expect(!viewModel.isEmpty)
  }

  @Test("a successful load clears loading and publishes the rows")
  func loadsSuccessfully() async {
    let viewModel = makeViewModel(StubRepository(.success([studio("1", "Family")])))

    await viewModel.load()

    #expect(!viewModel.isLoading)
    #expect(viewModel.studios.map(\.name) == ["Family"])
    #expect(viewModel.error == nil)
  }

  @Test("a failure clears loading and exposes the error")
  func exposesFailure() async {
    let viewModel = makeViewModel(StubRepository(.failure(.offline)))

    await viewModel.load()

    #expect(!viewModel.isLoading)
    #expect(viewModel.error == .offline)
  }

  @Test("an empty result reads as empty only once loading is done")
  func emptyAfterLoad() async {
    let viewModel = makeViewModel(StubRepository(.success([])))

    await viewModel.load()

    #expect(viewModel.isEmpty)
  }

  @Test("a failed refresh keeps the rows that are already on screen")
  func failedRefreshKeepsRows() async {
    let repository = StubRepository(.success([studio("1", "Family")]))
    let viewModel = makeViewModel(repository)
    await viewModel.load()
    #expect(viewModel.studios.count == 1)

    repository.response = .failure(.timeout)
    await viewModel.refresh()

    #expect(viewModel.error == .timeout)
    // The regression this guards: wiping real content because a background
    // reload failed.
    #expect(viewModel.studios.count == 1)
    #expect(!viewModel.isRefreshing)
  }

  @Test("refresh does not raise the full-screen loader that hides the list")
  func refreshDoesNotBlankTheScreen() async {
    let repository = StubRepository(.success([studio("1", "Family")]))
    let viewModel = makeViewModel(repository)
    await viewModel.load()

    // `refresh()` sets isLoading = false before awaiting, so the flag is
    // observably false for the whole in-flight window. Asserting it after the
    // await still catches the mistake this guards against — a refresh path that
    // reuses load()'s isLoading = true.
    await viewModel.refresh()

    #expect(!viewModel.isLoading)
    #expect(viewModel.studios.count == 1)
  }

  @Test("the use case orders most-recently-updated first")
  func ordersByUpdatedAt() async {
    let repository = StubRepository(
      .success([
        studio("1", "Older", updatedAt: "2026-08-01T00:00:00.000Z"),
        studio("2", "Newer", updatedAt: "2026-08-10T00:00:00.000Z"),
      ])
    )
    let viewModel = makeViewModel(repository)

    await viewModel.load()

    // Same rule as GetStudiosUseCase in weekclip-android. The two clients
    // sorting differently would be a bug nobody files and everybody notices.
    #expect(viewModel.studios.map(\.name) == ["Newer", "Older"])
  }

  @Test("studios with no timestamp sort last, then by name")
  func nilTimestampsSortLast() async {
    let repository = StubRepository(
      .success([
        studio("1", "Bravo"),
        studio("2", "Dated", updatedAt: "2026-08-01T00:00:00.000Z"),
        studio("3", "Alpha"),
      ])
    )
    let viewModel = makeViewModel(repository)

    await viewModel.load()

    #expect(viewModel.studios.map(\.name) == ["Dated", "Alpha", "Bravo"])
  }
}
