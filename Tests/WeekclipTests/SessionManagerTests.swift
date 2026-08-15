import XCTest

@testable import WeekclipData

/// Doubles shared by the session tests.
actor RecordingSessionStore: SessionStore {
  private var stored: ProfileSession?
  private(set) var reads = 0
  private(set) var writes = 0
  private(set) var clears = 0

  init(_ stored: ProfileSession? = nil) {
    self.stored = stored
  }

  func read() async -> ProfileSession? {
    reads += 1
    return stored
  }

  func write(_ session: ProfileSession) async {
    writes += 1
    stored = session
  }

  func clear() async {
    clears += 1
    stored = nil
  }

  func peek() -> ProfileSession? { stored }
  func counts() -> (reads: Int, writes: Int, clears: Int) { (reads, writes, clears) }
}

/// A refresher whose outcome is scripted and whose calls are counted.
///
/// `hold` lets a test keep one refresh open while other callers pile up, which
/// is how single-flight is proven rather than asserted.
actor ScriptedRefresher: SessionRefresher {
  private let outcome: @Sendable (ProfileSession) -> RefreshOutcome
  private var gate: CheckedContinuation<Void, Never>?
  private var held = false
  private(set) var calls = 0

  init(hold: Bool = false, outcome: @escaping @Sendable (ProfileSession) -> RefreshOutcome) {
    self.outcome = outcome
    self.held = hold
  }

  func refresh(_ session: ProfileSession) async -> RefreshOutcome {
    calls += 1
    if held {
      await withCheckedContinuation { continuation in
        gate = continuation
      }
    }
    return outcome(session)
  }

  func release() {
    held = false
    gate?.resume()
    gate = nil
  }

  func callCount() -> Int { calls }
}

func session(
  accessToken: String = "access-1",
  refreshToken: String = "refresh-1",
  expiresAt: Int = 10_000,
  userID: String = "user-1"
) -> ProfileSession {
  ProfileSession(
    accessToken: accessToken,
    refreshToken: refreshToken,
    expiresAtEpochSeconds: expiresAt,
    userID: userID
  )
}

/// The rules that decide whether a user stays signed in.
///
/// Every case here is one the app will actually meet: an hourly rotation, a
/// phone in a lift, a revoked account, several screens loading at once. Expiry
/// is driven by an injected clock rather than by sleeping, which is the only
/// reason a test for "the token expired an hour in" finishes in milliseconds.
final class SessionManagerTests: XCTestCase {
  private let configured = AuthConfig(
    supabaseURL: URL(string: "https://project.supabase.co"),
    anonKey: "anon-key"
  )

  private func manager(
    store: any SessionStore,
    refresher: any SessionRefresher,
    now: Int,
    config: AuthConfig? = nil
  ) -> SessionManager {
    SessionManager(
      store: store,
      refresher: refresher,
      authConfig: config ?? configured,
      now: { now }
    )
  }

  func testTokenWithLifeLeftIsHandedOutWithoutTouchingTheNetwork() async {
    let store = RecordingSessionStore(session(expiresAt: 10_000))
    let refresher = ScriptedRefresher { _ in
      XCTFail("must not refresh"); return .unavailable
    }

    let token = await manager(store: store, refresher: refresher, now: 5_000).accessToken()

    XCTAssertEqual(token, "access-1")
    let calls = await refresher.callCount()
    XCTAssertEqual(calls, 0)
  }

  func testTokenInsideTheSkewWindowIsRefreshedBeforeItIsUsed() async {
    // 30s of life left, and the skew is 60s: still valid by the clock, but not
    // for long enough to survive the round trip it is about to make.
    let store = RecordingSessionStore(session(expiresAt: 10_000))
    let refresher = ScriptedRefresher { _ in
      .refreshed(session(accessToken: "access-2", expiresAt: 13_570))
    }

    let token = await manager(store: store, refresher: refresher, now: 9_970).accessToken()

    XCTAssertEqual(token, "access-2")
    let stored = await store.peek()
    XCTAssertEqual(stored?.accessToken, "access-2")
  }

  func testConcurrentCallersThatAllFindAStaleTokenCauseExactlyOneRefresh() async {
    // An actor is not a lock: every `await` is a suspension point, so without a
    // shared in-flight task each caller starts its own refresh. Supabase
    // rotates the refresh token on use, so the second and third would present
    // one the first already invalidated — signing the user out with their own
    // app.
    let store = RecordingSessionStore(session(expiresAt: 100))
    let refresher = ScriptedRefresher(hold: true) { _ in
      .refreshed(session(accessToken: "access-2", expiresAt: 3_700))
    }
    let subject = manager(store: store, refresher: refresher, now: 90)

    async let tokens = withTaskGroup(of: String?.self) { group -> [String?] in
      for _ in 0..<8 {
        group.addTask { await subject.accessToken() }
      }
      return await group.reduce(into: []) { $0.append($1) }
    }

    // Give every caller a chance to reach the shared task before releasing it.
    try? await Task.sleep(nanoseconds: 50_000_000)
    await refresher.release()

    let results = await tokens
    XCTAssertEqual(results.compactMap { $0 }.count, 8)
    XCTAssertTrue(results.allSatisfy { $0 == "access-2" })
    let calls = await refresher.callCount()
    XCTAssertEqual(calls, 1, "each caller started its own refresh")
  }

  func testRefreshThatCannotReachTheNetworkKeepsTheSession() async {
    // The device clock is the only reason we believe this expired. The server
    // decides, and it has not been asked yet.
    let store = RecordingSessionStore(session(expiresAt: 100))
    let refresher = ScriptedRefresher { _ in .unavailable }

    let token = await manager(store: store, refresher: refresher, now: 90).accessToken()

    XCTAssertEqual(token, "access-1")
    let stored = await store.peek()
    XCTAssertNotNil(stored)
    let counts = await store.counts()
    XCTAssertEqual(counts.clears, 0)
  }

  func testRefreshTheProviderRefusesSignsTheUserOut() async {
    let store = RecordingSessionStore(session(expiresAt: 100))
    let refresher = ScriptedRefresher { _ in .rejected }
    let subject = manager(store: store, refresher: refresher, now: 90)

    let token = await subject.accessToken()

    XCTAssertNil(token)
    let stored = await store.peek()
    XCTAssertNil(stored)
    let state = await subject.state
    XCTAssertEqual(state, .signedOut)
  }

  func testAfterA401TheSameTokenIsNotHandedBackOnAnUnreachableNetwork() async {
    // Mirror image of the case above: here the server HAS spoken, and
    // re-sending what it just rejected is a guaranteed second failure.
    let store = RecordingSessionStore(session(expiresAt: 10_000))
    let refresher = ScriptedRefresher { _ in .unavailable }
    let subject = manager(store: store, refresher: refresher, now: 0)

    let token = await subject.accessTokenAfterUnauthorized(failedCredential: "access-1")

    XCTAssertNil(token)
    let stored = await store.peek()
    XCTAssertNotNil(stored)
  }

  func testA401CarryingASupersededTokenDoesNotTriggerASecondRefresh() async {
    // Several requests were in flight when the token rotated. The stragglers
    // come back 401 holding the OLD token; refreshing again for each of them is
    // the rotation stampede, one layer out.
    let store = RecordingSessionStore(session(accessToken: "access-2"))
    let refresher = ScriptedRefresher { _ in
      XCTFail("must not refresh"); return .unavailable
    }
    let subject = manager(store: store, refresher: refresher, now: 0)

    let token = await subject.accessTokenAfterUnauthorized(failedCredential: "access-1")

    XCTAssertEqual(token, "access-2")
    let calls = await refresher.callCount()
    XCTAssertEqual(calls, 0)
  }

  func testBuildWithNoProjectKeyReportsASignOutInsteadOfRetryingForever() async {
    // Release builds ship a blank anon key until the OAuth clients exist
    // (148.5c-b), so this branch is reachable in a shipped binary.
    let store = RecordingSessionStore(session(expiresAt: 100))
    let refresher = ScriptedRefresher { _ in
      XCTFail("must not refresh"); return .unavailable
    }
    let subject = manager(
      store: store,
      refresher: refresher,
      now: 90,
      config: AuthConfig(supabaseURL: URL(string: "https://project.supabase.co"), anonKey: "")
    )

    let token = await subject.accessToken()

    XCTAssertNil(token)
    let state = await subject.state
    XCTAssertEqual(state, .signedOut)
  }

  func testAnAdoptedSessionIsPersistedAndPublished() async {
    let store = RecordingSessionStore()
    let refresher = ScriptedRefresher { _ in .unavailable }
    let subject = manager(store: store, refresher: refresher, now: 0)

    await subject.adopt(session(userID: "user-9"))

    let stored = await store.peek()
    XCTAssertEqual(stored?.userID, "user-9")
    let state = await subject.state
    XCTAssertEqual(state, .signedIn(userID: "user-9"))
  }

  func testStateIsUnknownUntilTheStoreHasBeenRead() async {
    // Not "signed out": a UI that conflates the two shows a login screen to
    // someone who is signed in, for as long as the keychain read takes.
    let store = RecordingSessionStore(session())
    let refresher = ScriptedRefresher { _ in .unavailable }
    let subject = manager(store: store, refresher: refresher, now: 0)

    let before = await subject.state
    XCTAssertEqual(before, .unknown)

    let after = await subject.reload()
    XCTAssertEqual(after, .signedIn(userID: "user-1"))
  }

  func testTheStoreIsReadOnceAndThenCached() async {
    let store = RecordingSessionStore(session(expiresAt: 10_000))
    let refresher = ScriptedRefresher { _ in .unavailable }
    let subject = manager(store: store, refresher: refresher, now: 0)

    for _ in 0..<5 {
      _ = await subject.accessToken()
    }

    let counts = await store.counts()
    XCTAssertEqual(counts.reads, 1)
  }
}
