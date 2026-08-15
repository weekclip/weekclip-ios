import Foundation
import WeekclipShared

/// The one thing that knows whether this app has a session, and the only thing
/// allowed to change that.
///
/// ### An actor is not a lock
///
/// This is the trap on this platform, and it is the reason `inFlightRefresh`
/// exists. Actor isolation guarantees that only one task runs *between*
/// suspension points — but every `await` is a suspension point, and at each one
/// another task may enter. So this:
///
///     if !session.isUsable { await refresher.refresh(session) }   // WRONG
///
/// serialises nothing useful: three callers can each pass the `isUsable` check
/// and each start their own refresh. Supabase **rotates the refresh token on
/// use**, so the second and third would present a token the first has already
/// invalidated, and the user is signed out by their own app.
///
/// The fix is to share the `Task`, not to trust the actor: the first caller
/// stores it, everyone else awaits the same one. The Android side gets this
/// from a `Mutex` held across the whole call, which its blocking-friendly
/// runtime allows; here the structured-concurrency equivalent is a shared task.
public actor SessionManager {
  private let store: any SessionStore
  private let refresher: any SessionRefresher
  private let authConfig: AuthConfig
  private let now: @Sendable () -> Int

  /// Mirrors the store so the common path costs no keychain read.
  private var cached: ProfileSession?
  private var loadedFromStore = false
  private var inFlightRefresh: Task<RefreshOutcome, Never>?

  public init(
    store: any SessionStore,
    refresher: any SessionRefresher,
    authConfig: AuthConfig,
    now: @escaping @Sendable () -> Int = { Int(Date().timeIntervalSince1970) }
  ) {
    self.store = store
    self.refresher = refresher
    self.authConfig = authConfig
    self.now = now
  }

  public var state: SessionState {
    guard loadedFromStore else { return .unknown }
    guard let cached else { return .signedOut }
    return .signedIn(userID: cached.userID)
  }

  /// The token to put on the next request, refreshing first if it is about to
  /// expire.
  public func accessToken() async -> String? {
    guard let session = await loadIfNeeded() else { return nil }
    if session.isUsable(at: now()) {
      return session.accessToken
    }
    return await renew(session, keepOnFailure: true)?.accessToken
  }

  /// Called after the server has already answered 401 with `failedCredential`.
  ///
  /// The comparison is the point: with several requests in flight, the first
  /// 401 triggers a refresh and the rest arrive holding a token that is
  /// *already* superseded. Without the check each of them would refresh again —
  /// the rotation stampede, one layer out.
  public func accessTokenAfterUnauthorized(failedCredential: String?) async -> String? {
    guard let session = await loadIfNeeded() else { return nil }

    if let failedCredential, session.accessToken != failedCredential {
      // Someone else already refreshed. Hand back what they got.
      return session.accessToken
    }

    return await renew(session, keepOnFailure: false)?.accessToken
  }

  /// Takes ownership of a freshly minted grant (sign-in).
  public func adopt(_ session: ProfileSession) async {
    await persist(session)
  }

  public func signOut() async {
    await clear()
  }

  /// Forces the next read to go to the store. Exists for tests and for the
  /// first-launch path, which wants to know whether anything is stored *before*
  /// deciding to sign in.
  @discardableResult
  public func reload() async -> SessionState {
    loadedFromStore = false
    _ = await loadIfNeeded()
    return state
  }

  private func loadIfNeeded() async -> ProfileSession? {
    if !loadedFromStore {
      cached = await store.read()
      loadedFromStore = true
    }
    return cached
  }

  /// - Parameters:
  ///   - session: the session that needs renewing.
  ///   - keepOnFailure: what to do when the refresh could not be *attempted*
  ///     successfully. On the proactive path the answer is to hand back the old
  ///     token anyway: the device clock is the only reason we believed it
  ///     expired, and **the server is the authority on expiry**. A phone whose
  ///     clock has drifted ten minutes fast would otherwise throw away a token
  ///     that is still perfectly valid, and the 401 that comes back if it
  ///     really has expired is handled one layer up. On the reactive path the
  ///     server has already said 401, so re-sending it is a guaranteed second
  ///     failure.
  /// - Returns: the session to use now, or nil if there is none.
  private func renew(_ session: ProfileSession, keepOnFailure: Bool) async -> ProfileSession? {
    guard authConfig.isConfigured else {
      // No project key compiled in — nothing can renew this and nothing will.
      // Reporting a clean sign-out beats an endless loop of doomed requests.
      await clear()
      return nil
    }

    switch await sharedRefresh(of: session) {
    case .refreshed:
      // The originating call already persisted; `cached` is the single answer,
      // which also means a joiner sees the same session rather than its own
      // copy of the outcome.
      return cached
    case .rejected:
      return nil
    case .unavailable:
      return keepOnFailure ? cached : nil
    }
  }

  /// Runs one refresh at a time and lets every other caller await the same one.
  ///
  /// **The store update happens inside the shared task, not after it**, and
  /// that ordering is load-bearing. The obvious arrangement — await the task,
  /// then persist — has the same shape of bug this type exists to prevent: the
  /// joiners are woken the instant the task completes, while the originator is
  /// still suspended inside `persist`, so they read the *old* `cached` value
  /// and hand out the token that was just replaced. Caught by
  /// `testConcurrentCallersThatAllFindAStaleTokenCauseExactlyOneRefresh`, which
  /// counted one refresh (correct) but saw callers walk away with two different
  /// tokens.
  ///
  /// The Android side does not need this: its `Mutex` is held across the whole
  /// call including the write, so no other caller can observe the gap. Here the
  /// gap is an `await`, and every `await` is somewhere another task can run.
  private func sharedRefresh(of session: ProfileSession) async -> RefreshOutcome {
    if let inFlightRefresh {
      // Joiners deliberately do NOT persist: the shared task already did, and
      // doing it twice would write the same session twice and clear it twice
      // on rejection.
      return await inFlightRefresh.value
    }

    let task = Task { [refresher] () -> RefreshOutcome in
      let outcome = await refresher.refresh(session)
      await self.apply(outcome)
      return outcome
    }
    inFlightRefresh = task
    let outcome = await task.value
    inFlightRefresh = nil

    return outcome
  }

  private func apply(_ outcome: RefreshOutcome) async {
    switch outcome {
    case .refreshed(let renewed):
      await persist(renewed)
    case .rejected:
      AppLog.session.info("refresh token was rejected; signing out")
      await clear()
    case .unavailable:
      break
    }
  }

  private func persist(_ session: ProfileSession) async {
    await store.write(session)
    cached = session
    loadedFromStore = true
  }

  private func clear() async {
    await store.clear()
    cached = nil
    loadedFromStore = true
  }
}
