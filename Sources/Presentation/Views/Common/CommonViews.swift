import SwiftUI

// MARK: - Empty State View

public struct EmptyStateView: View {
  let icon: String
  let title: String
  let message: String

  public var body: some View {
    VStack(spacing: 16) {
      Image(systemName: icon)
        .font(.system(size: 48))
        .foregroundStyle(.secondary)

      Text(title)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(.primary)

      Text(message)
        .font(.system(size: 14, weight: .regular))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .lineLimit(3)
    }
    .padding(40)
  }
}

// MARK: - Error Banner

public struct ErrorBannerView: View {
  let error: Error
  let dismissAction: () -> Void

  public var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 12) {
        Image(systemName: "exclamationmark.circle.fill")
          .font(.system(size: 16))
          .foregroundStyle(.red)

        VStack(alignment: .leading, spacing: 2) {
          Text("Error")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)

          if let localError = error as? LocalizedError,
             let description = localError.errorDescription {
            Text(description)
              .font(.system(size: 12, weight: .regular))
              .foregroundStyle(.secondary)
              .lineLimit(2)
          } else {
            Text(error.localizedDescription)
              .font(.system(size: 12, weight: .regular))
              .foregroundStyle(.secondary)
              .lineLimit(2)
          }
        }

        Spacer()

        Button(action: dismissAction) {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 16))
            .foregroundStyle(.secondary)
        }
      }
      .padding(12)
      .background(Color(red: 1.0, green: 0.95, blue: 0.95))
      .cornerRadius(8)
    }
  }
}

// MARK: - Placeholder Image View

public struct PlaceholderImageView: View {
  public var body: some View {
    ZStack {
      Color(red: 0.95, green: 0.95, blue: 0.97)

      VStack(spacing: 8) {
        Image(systemName: "photo")
          .font(.system(size: 24))
          .foregroundStyle(.secondary)

        Text("No Image")
          .font(.system(size: 12, weight: .regular))
          .foregroundStyle(.secondary)
      }
    }
  }
}

// MARK: - Loading Spinner

public struct LoadingSpinner: View {
  @State private var isAnimating = false

  public var body: some View {
    ZStack {
      Circle()
        .stroke(
          Color.blue.opacity(0.2),
          lineWidth: 4
        )

      Circle()
        .trim(from: 0, to: 0.7)
        .stroke(
          Color.blue,
          style: StrokeStyle(lineWidth: 4, lineCap: .round)
        )
        .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
        .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
    }
    .frame(width: 40, height: 40)
    .onAppear {
      isAnimating = true
    }
  }
}

// MARK: - Responsive Grid Item

public struct ResponsiveGridItem<Content: View>: View {
  let content: () -> Content

  public var body: some View {
    content()
  }
}

#Preview {
  VStack(spacing: 24) {
    EmptyStateView(
      icon: "film",
      title: "No Media",
      message: "This studio doesn't have any media yet"
    )

    ErrorBannerView(
      error: NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error message"]),
      dismissAction: {}
    )

    PlaceholderImageView()
      .frame(height: 100)

    LoadingSpinner()
  }
  .padding(16)
  .background(Color(red: 0.95, green: 0.95, blue: 0.97))
}
