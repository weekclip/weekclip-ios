import OSLog

/// Logging.
///
/// `os.Logger`, not swift-log. It is on every OS the app supports, it is what
/// Console.app and a sysdiagnose read, and its interpolation is lazy — a
/// `.debug` call in a hot path costs nothing when nobody is listening. The
/// dependency it replaces existed only to wrap it.
///
/// The subsystem is the bundle identifier so log entries filter cleanly
/// alongside crash reports. It is `cc.sunglint.weekclip` on both platforms
/// (PRD-0008, 2026-08-14) — the old value here was `com.weekclip.ios`.
public enum AppLog {
  private static let subsystem = "cc.sunglint.weekclip"

  /// Networking: requests, status codes, decode failures.
  public static let network = Logger(subsystem: subsystem, category: "network")

  /// Navigation and deep-link resolution.
  public static let navigation = Logger(subsystem: subsystem, category: "navigation")

  /// View models and state transitions.
  public static let ui = Logger(subsystem: subsystem, category: "ui")
}
