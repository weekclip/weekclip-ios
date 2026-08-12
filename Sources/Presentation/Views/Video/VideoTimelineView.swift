import SwiftUI

/// Seek bar with current position and buffered position indicators
struct VideoTimelineView: View {
  @Bindable var viewModel: VideoPlayerViewModel
  @State private var isDragging = false

  var body: some View {
    VStack(spacing: 8) {
      ZStack(alignment: .leading) {
        // Background track
        Capsule()
          .fill(Color.white.opacity(0.3))
          .frame(height: 4)

        // Buffered progress
        if viewModel.duration > 0 {
          Capsule()
            .fill(Color.white.opacity(0.6))
            .frame(width: (viewModel.bufferedDuration / viewModel.duration) * 300, height: 4)
        }

        // Current progress
        if viewModel.duration > 0 {
          Capsule()
            .fill(Color.white)
            .frame(width: (viewModel.currentTime / viewModel.duration) * 300, height: 4)
        }

        // Draggable slider
        Slider(
          value: $viewModel.currentTime,
          in: 0...(viewModel.duration > 0 ? viewModel.duration : 1),
          step: 0.1
        )
        .tint(.white)
        .onChange(of: viewModel.currentTime) { oldValue, newValue in
          if isDragging {
            viewModel.seek(to: newValue)
          }
        }
        .gesture(
          DragGesture()
            .onChanged { _ in
              isDragging = true
            }
            .onEnded { _ in
              isDragging = false
              viewModel.seek(to: viewModel.currentTime)
            }
        )
      }
      .frame(height: 20)

      // Time labels
      HStack(spacing: 0) {
        Text(formatTime(viewModel.currentTime))
          .font(.system(size: 12, weight: .regular))
          .foregroundStyle(.white)

        Spacer()

        Text(formatTime(viewModel.duration))
          .font(.system(size: 12, weight: .regular))
          .foregroundStyle(.white)
      }
    }
  }

  private func formatTime(_ seconds: TimeInterval) -> String {
    guard !seconds.isNaN && !seconds.isInfinite else { return "0:00" }

    let minutes = Int(seconds) / 60
    let secs = Int(seconds) % 60
    return String(format: "%d:%02d", minutes, secs)
  }
}

#Preview {
  @Previewable @State var viewModel = VideoPlayerViewModel(studioId: "1", mediaId: "1")

  ZStack {
    Color.black
      .ignoresSafeArea()

    VideoTimelineView(viewModel: viewModel)
      .padding()
  }
}
