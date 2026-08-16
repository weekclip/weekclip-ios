import SwiftUI
import WeekclipDomain
import WeekclipShared

/// The dashboard.
///
/// State comes from `DashboardViewModel`; this file decides only what it looks
/// like and what copy it uses. Accessibility identifiers are set explicitly
/// because that is what `maestro/` selects on — SwiftUI does not derive one
/// from a label.
public struct DashboardView: View {
  @State private var viewModel: DashboardViewModel

  private let onSelect: (Studio) -> Void

  public init(viewModel: DashboardViewModel, onSelect: @escaping (Studio) -> Void) {
    _viewModel = State(initialValue: viewModel)
    self.onSelect = onSelect
  }

  public var body: some View {
    content
      .navigationTitle(Text("Studios", comment: "Dashboard screen title"))
      // The start destination, so this is the app's masthead. The mark goes in
      // the bar's leading slot rather than `.principal`, which would REPLACE
      // the title view — and `maestro/smoke.yaml` asserts the literal text
      // "Studios" is visible. The root of the stack has no back button, so the
      // slot is free.
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          WeekclipLogoMark(size: .small)
        }
      }
      // `.task` and not `.onAppear`: it is cancelled when the view goes away,
      // so a fast back-swipe does not leave a request running against a view
      // model nobody will read.
      .task { await viewModel.load() }
  }

  @ViewBuilder
  private var content: some View {
    if viewModel.state.showFullScreenLoader {
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("dashboard-loading")
    } else if let error = viewModel.state.error {
      errorState(error)
    } else if viewModel.state.isEmpty {
      ContentUnavailableView(
        "No studios yet",
        systemImage: "rectangle.stack",
        description: Text("Studios you create or join will appear here.")
      )
      .accessibilityIdentifier("dashboard-empty")
    } else {
      List(viewModel.state.studios) { studio in
        Button {
          onSelect(studio)
        } label: {
          row(studio)
        }
        .accessibilityIdentifier("studio-row")
      }
      .refreshable { await viewModel.refresh() }
      .accessibilityIdentifier("dashboard-list")
    }
  }

  private func row(_ studio: Studio) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(studio.name)
        .font(.weekclip(.headline))
      Text(roleLabel(studio.role))
        .font(.weekclip(.caption))
        .foregroundStyle(.secondary)
    }
    // One element instead of two, so VoiceOver announces "Family, Owner"
    // rather than stopping on each line.
    .accessibilityElement(children: .combine)
  }

  private func errorState(_ error: AppError) -> some View {
    VStack(spacing: 12) {
      Text(message(for: error))
        .font(.weekclip(.body))
        .multilineTextAlignment(.center)
      Button("Try again") {
        Task { await viewModel.refresh() }
      }
      .font(.weekclip(.callout))
      .accessibilityIdentifier("dashboard-retry")
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityIdentifier("dashboard-error")
  }

  /// Error -> copy.
  ///
  /// An exhaustive `switch`, so a new `AppError` case fails to compile here
  /// rather than falling through to a generic message nobody notices is wrong.
  ///
  /// PRD-0008 D3: none of these name a way to pay. Capacity is not in this set
  /// at all yet — when it is, the copy states the fact and stops there.
  private func message(for error: AppError) -> LocalizedStringKey {
    switch error {
    case .offline:
      return "You appear to be offline."
    case .timeout:
      return "The server took too long to respond."
    case .unauthorized:
      return "Your session has ended. Sign in again."
    case .notFound:
      return "That is no longer available."
    case .malformedResponse, .server, .unexpected:
      return "Something went wrong. Please try again."
    }
  }

  private func roleLabel(_ role: StudioRole) -> LocalizedStringKey {
    switch role {
    case .owner: return "Owner"
    case .editor: return "Editor"
    case .viewer: return "Viewer"
    case .unknown: return "Member"
    }
  }
}
