import SwiftUI
import WeekclipDomain

/// The launch gate's state (PRD-0008 D6①).
///
/// `checking` is a real state and the initial one. Starting at `allowed` would
/// flash the dashboard for a frame before a block landed — the same shape of
/// bug as 148.3d, where a refresh with no rows rendered as "No studios yet."
/// Starting at `blocked` would flash a force-update screen at everyone.
public enum AppGateState: Equatable, Sendable {
  case checking
  case allowed
  case updateRequired(storeURL: String?)
}

/// The terminal screen for a build the server no longer accepts.
///
/// Deliberately has no way past it. A dismissible banner would leave people
/// running a client the server has declared incompatible, which is the
/// situation the gate exists to end.
///
/// The store button is absent when there is no URL — iOS has no App Store
/// record yet (148.4c-b). Stating the fact without offering a button that goes
/// nowhere is the honest version.
struct UpdateRequiredView: View {
  let storeURL: String?

  var body: some View {
    VStack(spacing: 16) {
      // The only full-screen moment the app owns, and the one screen a blocked
      // user is guaranteed to see — so it is where the mark earns its place.
      // Above the title, not replacing it: `screen-title` is a maestro
      // selector.
      WeekclipLogoMark(size: .extraLarge)

      Text("Update Weekclip to continue")
        .font(.weekclip(.title3))
        .multilineTextAlignment(.center)
        .accessibilityIdentifier("screen-title")

      Text("This version is no longer supported.")
        .font(.weekclip(.body))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      if let storeURL, let url = URL(string: storeURL) {
        Link("Open the store", destination: url)
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier("update-open-store")
      }
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
