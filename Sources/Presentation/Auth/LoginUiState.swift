import WeekclipShared

/// The login screen in one value.
///
/// The four states are the four the wireframe draws
/// (`weekclip-design-system/apps/wireframes/screens/auth/mobile.html`): the
/// form, `loading`, `error`, and `denied`. One `phase` plus one `error` rather
/// than four flags, for the reason `DashboardUiState` gives — separate flags
/// let a view render a combination that never legally exists.
public struct LoginUiState: Equatable, Sendable {
  public var phase: LoginPhase
  public var error: LoginError?

  /// A deep link is waiting behind the sign-in. The screen says so, because the
  /// wireframe's "딥링크 복귀" zone exists to answer the question a user asks
  /// when an unexpected login screen appears: *did it forget what I tapped?*
  public var hasIntendedDestination: Bool

  /// The label of a debug-only way in, or nil when there is none.
  ///
  /// Always nil in a release build — the whole affordance is behind
  /// `#if DEBUG`, so the button is absent from the binary rather than hidden in
  /// it. The label travels with it rather than living in this module's strings
  /// for the same reason: a string a release build cannot reach would ship
  /// anyway.
  public var debugSignInLabel: String?

  public init(
    phase: LoginPhase = .idle,
    error: LoginError? = nil,
    hasIntendedDestination: Bool = false,
    debugSignInLabel: String? = nil
  ) {
    self.phase = phase
    self.error = error
    self.hasIntendedDestination = hasIntendedDestination
    self.debugSignInLabel = debugSignInLabel
  }

  /// The whole point of the wireframe's `loading` state: *"앱은 외부 브라우저로
  /// 나갔다 돌아온다. 돌아오는 동안 이 화면이 남아 있어야 한다."* Both busy
  /// phases keep the screen — one waiting for the browser, one waiting for the
  /// exchange — and the user cannot tell them apart, which is correct.
  public var isBusy: Bool { phase != .idle }
}

public enum LoginPhase: Equatable, Sendable {
  case idle

  /// The authentication sheet is up; waiting for a redirect or a cancel.
  case connecting

  /// Redirect received; trading the authorization code for a session.
  case exchanging
}

/// Why sign-in did not happen, in the terms the screen distinguishes.
///
/// Not `AppError` directly: the two states the wireframe draws separately —
/// "로그인하지 못했다" (retry works) and "돌아갈 곳을 잃었다" (retry does not) —
/// are not a distinction `AppError` makes, and never should be. That one is
/// about transport; this one is about the sign-in.
public enum LoginError: Equatable, Sendable {
  /// Google or the user refused. Retrying just shows the same prompt.
  case denied(reason: String)

  /// No Supabase project key in this build, so there is nothing to sign in to.
  /// A state, not a bug — see `AuthConfig.isConfigured`.
  case notConfigured

  /// The round trip broke somewhere. Retrying is the sensible move.
  case failed(cause: AppError)

  /// The browser sheet itself failed to run.
  case browserUnavailable
}
