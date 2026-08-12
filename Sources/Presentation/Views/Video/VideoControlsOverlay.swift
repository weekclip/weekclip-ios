import SwiftUI

/// Custom video player controls overlay
struct VideoControlsOverlay: View {
  @Bindable var viewModel: VideoPlayerViewModel
  @Environment(\.dismiss) var dismiss
  let mediaTitle: String

  var body: some View {
    ZStack {
      // Tap to toggle controls
      if viewModel.showControls {
        Color.black.opacity(0.3)
          .onTapGesture {
            viewModel.toggleControls()
          }
      }

      VStack(spacing: 0) {
        // Top bar
        HStack(spacing: 12) {
          Button(action: { dismiss() }) {
            Image(systemName: "chevron.left")
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(.white)
              .frame(width: 40, height: 40)
          }

          Text(mediaTitle)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)

          Spacer()
        }
        .padding(12)
        .opacity(viewModel.showControls ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: viewModel.showControls)

        Spacer()

        // Center play/pause button
        if viewModel.showControls {
          VStack {
            if viewModel.isBuffering {
              ProgressView()
                .tint(.white)
            } else {
              Button(action: { viewModel.togglePlayPause() }) {
                Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                  .font(.system(size: 64))
                  .foregroundStyle(.white)
              }
            }
          }
          .transition(.scale.combined(with: .opacity))
        }

        Spacer()

        // Bottom controls
        VStack(spacing: 12) {
          // Timeline
          VideoTimelineView(viewModel: viewModel)
            .padding(.horizontal, 12)

          // Controls row
          HStack(spacing: 12) {
            // Volume slider
            VStack(spacing: 4) {
              Image(systemName: viewModel.isMuted ? "speaker.slash.fill" : "speaker.2.fill")
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .frame(width: 30)

              Slider(value: $viewModel.volume, in: 0...1)
                .tint(.white)
                .onChange(of: viewModel.volume) { oldValue, newValue in
                  viewModel.setVolume(newValue)
                }
                .frame(height: 4)
            }
            .frame(width: 50)

            Spacer()

            // Mute button
            Button(action: { viewModel.toggleMute() }) {
              Image(systemName: viewModel.isMuted ? "speaker.slash.circle.fill" : "speaker.circle")
                .font(.system(size: 20))
                .foregroundStyle(.white)
            }

            // Fullscreen button
            Button(action: { viewModel.toggleFullscreen() }) {
              Image(systemName: viewModel.isFullscreen ? "compress" : "expand")
                .font(.system(size: 20))
                .foregroundStyle(.white)
            }
          }
          .padding(.horizontal, 12)
          .padding(.bottom, 8)
        }
        .padding(12)
        .background(
          LinearGradient(
            gradient: Gradient(
              colors: [
                Color.black.opacity(0),
                Color.black.opacity(0.3),
                Color.black.opacity(0.6),
              ]
            ),
            startPoint: .top,
            endPoint: .bottom
          )
        )
        .opacity(viewModel.showControls ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: viewModel.showControls)
      }
      .onTapGesture {
        viewModel.showControlsWithAutoHide()
      }
    }
    .onAppear {
      viewModel.showControlsWithAutoHide()
    }
  }
}

#Preview {
  @Previewable @State var viewModel = VideoPlayerViewModel(studioId: "1", mediaId: "1")

  ZStack {
    Color.black
      .ignoresSafeArea()

    VideoControlsOverlay(viewModel: viewModel, mediaTitle: "Sample Video")
  }
}
