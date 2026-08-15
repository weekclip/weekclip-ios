import Testing
import WeekclipDomain
import WeekclipShared

/// The rule that decides whether an installed app keeps working.
///
/// Two things are pinned here, and both are the kind that get written the wrong
/// way round exactly once — in production, for everybody, at the same time: the
/// comparison is **strictly below**, and **any failure means carry on**.
@Suite("GetAppUpdateRequirement")
struct GetAppUpdateRequirementTests {

  private struct StubRepository: AppReleaseRepository {
    let result: Result<AppReleasePolicy, AppError>
    func policy() async -> Result<AppReleasePolicy, AppError> { result }
  }

  private func useCase(
    minimumBuild: Int,
    storeURL: String? = "https://store.example/app"
  ) -> GetAppUpdateRequirement {
    GetAppUpdateRequirement(
      repository: StubRepository(
        result: .success(AppReleasePolicy(minimumBuild: minimumBuild, storeURL: storeURL))
      )
    )
  }

  @Test("a build below the minimum is blocked")
  func belowMinimumIsBlocked() async {
    let requirement = await useCase(minimumBuild: 10)(currentBuild: 9)

    #expect(requirement == .required(storeURL: "https://store.example/app"))
  }

  /// `>=` here would block the very release an operator just declared to be the
  /// floor — the one they are trying to force everyone onto.
  @Test("a build equal to the minimum keeps running")
  func equalToMinimumRuns() async {
    #expect(await useCase(minimumBuild: 10)(currentBuild: 10) == .notRequired)
  }

  @Test("a newer build than the minimum keeps running")
  func newerRuns() async {
    #expect(await useCase(minimumBuild: 10)(currentBuild: 11) == .notRequired)
  }

  /// The server's default. Both ends fail open, so it takes two deliberate acts
  /// to stop an app.
  @Test("a minimum of zero blocks nobody")
  func zeroBlocksNobody() async {
    #expect(await useCase(minimumBuild: 0)(currentBuild: 1) == .notRequired)
  }

  /// iOS has no App Store record yet (148.4c-b), and a listing can disappear.
  /// The screen states the fact without offering a button that goes nowhere.
  @Test("a blocked build with nowhere to send the user is still blocked")
  func blockedWithoutStoreURL() async {
    let requirement = await useCase(minimumBuild: 10, storeURL: nil)(currentBuild: 1)

    #expect(requirement == .required(storeURL: nil))
  }

  /// None of these is evidence that this build is too old. Blocking on them
  /// would turn any outage — including an outage of this very endpoint — into a
  /// force-update screen for the whole fleet, with the server that could take
  /// it back being the one that is down.
  ///
  /// `.unauthorized` is in the list on purpose: off the VPN the dev tier
  /// answers 403 with a Cloudflare page, which lands here as unauthorized.
  @Test(
    "every failure means carry on",
    arguments: [
      AppError.offline,
      AppError.timeout,
      AppError.unauthorized,
      AppError.notFound,
      AppError.malformedResponse,
      AppError.server(status: 500, code: nil, message: nil),
      AppError.unexpected(description: "boom"),
    ])
  func failuresCarryOn(error: AppError) async {
    let useCase = GetAppUpdateRequirement(repository: StubRepository(result: .failure(error)))

    #expect(await useCase(currentBuild: 1) == .notRequired)
  }
}
