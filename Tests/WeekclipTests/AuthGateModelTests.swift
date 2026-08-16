import Foundation
import Testing
import WeekclipData
import WeekclipShared

@testable import WeekclipPresentation

/// The first gate's rules, one test each.
///
/// This is where PRD-0008 D4 actually lives. Everything else about sign-in —
/// PKCE, the sheet, the exchange — is machinery that can be right while the
/// product rule is wrong, and the product rule is the thing a reader of this
/// repo in six months will want stated somewhere they can run.
@MainActor
@Suite("AuthGateModel")
struct AuthGateModelTests {

  /// A fresh `UserDefaults` suite per test. `.standard` would let one test's
  /// parked route decide the next one's outcome — and the failure would depend
  /// on execution order, which is the worst kind to debug.
  private func makeFlowStore() -> SignInFlowStore {
    let name = "AuthGateModelTests.\(UUID().uuidString)"
    return SignInFlowStore(defaults: UserDefaults(suiteName: name)!)
  }

  private func makeSessionManager(stored: ProfileSession? = nil) -> SessionManager {
    SessionManager(
      store: FakeSessionStore(stored: stored),
      refresher: NoopRefresher(),
      authConfig: AuthConfig(
        supabaseURL: URL(string: "https://project.supabase.co"),
        anonKey: "anon"
      ),
      now: { 0 }
    )
  }

  /// Starts `observe()` and waits for the gate to leave `.unknown`.
  ///
  /// Polling rather than a fixed sleep: the stream delivers on its own
  /// schedule, and a sleep long enough to be reliable is long enough to make
  /// the suite slow for no reason.
  private func start(_ model: AuthGateModel) async {
    Task { await model.observe() }
    await settle(until: { model.state != .unknown })
  }

  private func settle(until condition: () -> Bool) async {
    for _ in 0..<200 {
      if condition() { return }
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
  }

  @Test("renders nothing until the stored session has been read")
  func unknownUntilLoaded() async {
    let model = AuthGateModel(
      sessionManager: makeSessionManager(stored: .fixture()),
      flowStore: makeFlowStore()
    )

    // Before observation starts. Reporting `.signedOut` here is the bug this
    // state exists to prevent: it flashes a login screen at a signed-in user.
    #expect(model.state == .unknown)

    await start(model)
    #expect(model.state == .signedIn)
  }

  @Test("no stored session means the first screen is the gate")
  func signedOutShowsTheGate() async {
    let model = AuthGateModel(sessionManager: makeSessionManager(), flowStore: makeFlowStore())
    await start(model)

    #expect(model.state == .signedOut)
  }

  @Test("a share link opens with no account at all")
  func shareLinkIsGuestReachable() async {
    let flowStore = makeFlowStore()
    let model = AuthGateModel(sessionManager: makeSessionManager(), flowStore: flowStore)
    await start(model)

    model.handle(link: .share(token: "abc123"))

    // The single exception in D4, and it is the API's shape rather than a
    // preference — see `WeekclipRoute.isGuestReachable`.
    #expect(model.state == .guest(.share(token: "abc123")))
    // Nothing was parked: a guest is not a user on their way to signing in.
    #expect(flowStore.takeIntendedRoute() == nil)
  }

  @Test("an invite link goes through the gate and is remembered")
  func inviteLinkNeedsAnAccount() async {
    let flowStore = makeFlowStore()
    let model = AuthGateModel(sessionManager: makeSessionManager(), flowStore: flowStore)
    await start(model)

    model.handle(link: .invite(token: "tok"))

    // Accepting an invite attaches a studio to an account, so there has to be
    // an account. weekclip-web reaches the same conclusion in flow F3.
    #expect(model.state == .signedOut)
    #expect(flowStore.takeIntendedRoute() == "invite/tok")
  }

  @Test("signing in goes to the link that was interrupted, not the dashboard")
  func signingInResumesTheLink() async {
    let manager = makeSessionManager()
    let model = AuthGateModel(sessionManager: manager, flowStore: makeFlowStore())
    await start(model)

    model.handle(link: .media(studioID: "s1", mediaID: "m1"))
    #expect(model.state == .signedOut)

    await manager.adopt(.fixture())
    await settle(until: { model.state == .signedIn })

    #expect(model.pendingRoute == .media(studioID: "s1", mediaID: "m1"))
  }

  @Test("an intended route fires once")
  func pendingRouteIsConsumed() async {
    let manager = makeSessionManager()
    let model = AuthGateModel(sessionManager: manager, flowStore: makeFlowStore())
    await start(model)
    model.handle(link: .invite(token: "tok"))
    await manager.adopt(.fixture())
    await settle(until: { model.pendingRoute != nil })

    model.didNavigate()

    // Re-navigating on the next change would yank the user out of whatever they
    // opened next — the reason this is an instruction and not a state.
    #expect(model.pendingRoute == nil)
  }

  @Test("a link that arrives while signed in navigates instead of parking")
  func linkWhileSignedIn() async {
    let flowStore = makeFlowStore()
    let model = AuthGateModel(
      sessionManager: makeSessionManager(stored: .fixture()),
      flowStore: flowStore
    )
    await start(model)

    model.handle(link: .studio(id: "s1"))

    #expect(model.state == .signedIn)
    #expect(model.pendingRoute == .studio(id: "s1"))
    #expect(flowStore.takeIntendedRoute() == nil)
  }

  @Test("a share link while signed in opens inside the app, not as a guest")
  func shareLinkWhileSignedIn() async {
    let model = AuthGateModel(
      sessionManager: makeSessionManager(stored: .fixture()),
      flowStore: makeFlowStore()
    )
    await start(model)

    model.handle(link: .share(token: "abc123"))

    // The guest surface is for people with no account. Someone who has one gets
    // the same link inside the app, where `SessionAxis` picks the share
    // credential per request rather than the gate picking it for the session.
    #expect(model.state == .signedIn)
    #expect(model.pendingRoute == .share(token: "abc123"))
  }

  @Test("backing out of a shared album lands on the gate")
  func leavingGuestShowsTheGate() async {
    let model = AuthGateModel(sessionManager: makeSessionManager(), flowStore: makeFlowStore())
    await start(model)
    model.handle(link: .share(token: "abc123"))

    model.leaveGuest()

    // Not "close the app": someone who opened a shared album may well have an
    // account, and this is the only way for them to reach it.
    #expect(model.state == .signedOut)
  }

  @Test("a link that arrives before the store has been read is not decided early")
  func linkBeforeSessionIsKnown() async {
    let flowStore = makeFlowStore()
    let model = AuthGateModel(
      sessionManager: makeSessionManager(stored: .fixture()),
      flowStore: flowStore
    )

    // No `start` first — the session is still `.unknown`, which is exactly the
    // cold-start-from-a-link case. Deciding here would park the route and show
    // the gate to someone who is signed in.
    model.handle(link: .studio(id: "s1"))
    await start(model)

    #expect(model.state == .signedIn)
    #expect(model.pendingRoute == .studio(id: "s1"))
    #expect(flowStore.takeIntendedRoute() == nil)
  }

  @Test("a sign-out nobody asked for reaches the gate")
  func signOutReachesTheGate() async {
    let manager = makeSessionManager(stored: .fixture())
    let model = AuthGateModel(sessionManager: manager, flowStore: makeFlowStore())
    await start(model)
    #expect(model.state == .signedIn)

    // Stands in for the real case: GoTrue rejecting a refresh token, several
    // layers below any view. Without `SessionManager.stateStream` the app would
    // go on showing the dashboard and failing every request.
    await manager.signOut()
    await settle(until: { model.state == .signedOut })

    #expect(model.state == .signedOut)
  }
}

extension ProfileSession {
  fileprivate static func fixture(userID: String = "user-1") -> ProfileSession {
    ProfileSession(
      accessToken: "access-1",
      refreshToken: "refresh-1",
      expiresAtEpochSeconds: 10_000,
      userID: userID
    )
  }
}

private actor FakeSessionStore: SessionStore {
  private var stored: ProfileSession?

  init(stored: ProfileSession?) {
    self.stored = stored
  }

  func read() async -> ProfileSession? { stored }
  func write(_ session: ProfileSession) async { stored = session }
  func clear() async { stored = nil }
}

private struct NoopRefresher: SessionRefresher {
  func refresh(_ profile: ProfileSession) async -> RefreshOutcome { .unavailable }
}
