import WeekclipShared

/// Reads the server's client-compatibility policy for **this** platform.
public protocol AppReleaseRepository: Sendable {
  func policy() async -> Result<AppReleasePolicy, AppError>
}
