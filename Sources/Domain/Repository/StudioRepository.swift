import WeekclipShared

/// The domain's view of studio storage.
///
/// Declared in the domain, implemented in `WeekclipData`, consumed by
/// `WeekclipPresentation` — so the dependency arrow points inward and the
/// presentation layer can be tested with a stub that never opens a socket.
///
/// Returns `Result` rather than throwing. A throwing API pushes `do/catch` into
/// every view model, and the case easiest to forget — no network — is the one
/// people hit most.
///
/// `Sendable` because a view model is `@MainActor` and the implementation is
/// not: without it, Swift 6 rejects the call across the isolation boundary.
public protocol StudioRepository: Sendable {
  /// Studios the current session can see. An empty array is a valid success.
  func getStudios() async -> Result<[Studio], AppError>
}
