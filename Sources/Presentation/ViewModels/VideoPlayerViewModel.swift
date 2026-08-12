import Foundation
import AVFoundation
import WeekclipDomain
import WeekclipData
import WeekclipShared
import Combine

/// ViewModel for video playback control and state management
@Observable
public final class VideoPlayerViewModel {
  // MARK: - Public Properties (Observable)

  public var isPlaying: Bool = false
  public var currentTime: TimeInterval = 0
  public var duration: TimeInterval = 0
  public var bufferedDuration: TimeInterval = 0
  public var isBuffering: Bool = false
  public var isMuted: Bool = false
  public var volume: Float = 1.0
  public var isFullscreen: Bool = false
  public var error: WeekclipError?
  public var showControls: Bool = true
  public var posterImageUrl: URL?
  public var media: StudioMedia?

  // MARK: - Private Properties

  private let apiClient: StudioAPIClient
  private let studioId: String
  private let mediaId: String

  public let player: AVPlayer = AVPlayer()
  private var timeObserverToken: Any?
  private var statusObserverToken: NSKeyValueObservation?
  private var bufferingObserverToken: NSKeyValueObservation?
  private var playingObserverToken: NSKeyValueObservation?
  private var controlsHideTimer: Timer?
  private var cancellables = Set<AnyCancellable>()

  // MARK: - Initialization

  public init(
    studioId: String,
    mediaId: String,
    apiClient: StudioAPIClient = StudioAPIClient()
  ) {
    self.studioId = studioId
    self.mediaId = mediaId
    self.apiClient = apiClient

    setupPlayerObservers()
  }

  deinit {
    cleanup()
  }

  // MARK: - Public Methods

  /// Load video media and set up playback
  public func loadVideo(url: URL, posterUrl: URL? = nil) {
    let asset = AVAsset(url: url)
    let playerItem = AVPlayerItem(asset: asset)

    player.replaceCurrentItem(with: playerItem)
    self.posterImageUrl = posterUrl

    // Setup time observer for progress updates
    setupTimeObserver()
    setupBufferingObserver()
    setupPlaybackObserver()
  }

  /// Fetch media details from API and load video
  public func loadMediaFromAPI() async {
    isBuffering = true

    do {
      // Fetch media details to get the manifest URL
      let mediaList = try await apiClient.fetchMedia(
        studioId: studioId,
        limit: 100,
        lastId: nil
      )

      guard let media = mediaList.first(where: { $0.id == mediaId }) else {
        error = .notFound
        isBuffering = false
        return
      }

      self.media = media
      self.posterImageUrl = media.thumbnailUrl.flatMap { URL(string: $0) }

      // Check if video URL is available
      guard let manifestUrl = media.preview.manifestUrl,
            let videoUrl = URL(string: manifestUrl) else {
        error = WeekclipError.invalidURL("Video streaming URL not available")
        isBuffering = false
        return
      }

      loadVideo(url: videoUrl, posterUrl: posterImageUrl)
      isBuffering = false
    } catch {
      self.error = error as? WeekclipError ?? .networkError(error.localizedDescription)
      isBuffering = false
    }
  }

  /// Play video
  public func play() {
    player.play()
    isPlaying = true
  }

  /// Pause video
  public func pause() {
    player.pause()
    isPlaying = false
  }

  /// Toggle play/pause
  public func togglePlayPause() {
    if isPlaying {
      pause()
    } else {
      play()
    }
  }

  /// Seek to specific time
  public func seek(to timeInterval: TimeInterval) {
    let cmTime = CMTime(seconds: timeInterval, preferredTimescale: 1000)
    player.seek(to: cmTime)
    currentTime = timeInterval
  }

  /// Set volume (0.0 to 1.0)
  public func setVolume(_ value: Float) {
    let normalizedValue = max(0.0, min(1.0, value))
    player.volume = normalizedValue
    volume = normalizedValue
  }

  /// Toggle mute
  public func toggleMute() {
    if isMuted {
      player.volume = volume
    } else {
      player.volume = 0
    }
    isMuted = !isMuted
  }

  /// Toggle fullscreen
  public func toggleFullscreen() {
    isFullscreen = !isFullscreen
  }

  /// Clear error
  public func clearError() {
    error = nil
  }

  // MARK: - Private Methods

  private func setupTimeObserver() {
    // Remove existing observer if any
    if let token = timeObserverToken {
      player.removeTimeObserver(token)
    }

    // Add periodic time observer
    timeObserverToken = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.5, preferredTimescale: 1000),
      queue: .main
    ) { [weak self] time in
      self?.currentTime = time.seconds
      self?.updateBufferedDuration()
    }
  }

  private func setupBufferingObserver() {
    // Remove existing observer if any
    bufferingObserverToken?.invalidate()

    // Observe loading state
    bufferingObserverToken = player.currentItem?.observe(
      \.isPlaybackBufferEmpty,
      options: [.new, .old],
      changeHandler: { [weak self] _, _ in
        DispatchQueue.main.async {
          self?.isBuffering = self?.player.currentItem?.isPlaybackBufferEmpty ?? false
        }
      }
    )
  }

  private func setupPlaybackObserver() {
    // Remove existing observer if any
    playingObserverToken?.invalidate()

    // Observe current item's status
    playingObserverToken = player.currentItem?.observe(
      \.status,
      options: [.new, .old],
      changeHandler: { [weak self] item, _ in
        DispatchQueue.main.async {
          switch item.status {
          case .readyToPlay:
            self?.duration = item.duration.seconds
            self?.isBuffering = false
          case .failed:
            self?.error = WeekclipError.networkError("Video failed to load")
          default:
            break
          }
        }
      }
    )
  }

  private func setupPlayerObservers() {
    // Observe rate changes (play/pause)
    NotificationCenter.default.publisher(
      for: NSNotification.Name.AVPlayerItemDidPlayToEndTime,
      object: player.currentItem
    )
    .sink { [weak self] _ in
      self?.isPlaying = false
    }
    .store(in: &cancellables)
  }

  private func updateBufferedDuration() {
    if let currentItem = player.currentItem {
      let loadedRanges = currentItem.loadedTimeRanges

      if !loadedRanges.isEmpty,
         let timeRange = loadedRanges.last?.timeRangeValue {
        let bufferedStart = timeRange.start.seconds
        let bufferedDuration = timeRange.duration.seconds
        self.bufferedDuration = bufferedStart + bufferedDuration
      }
    }
  }

  private func cleanup() {
    controlsHideTimer?.invalidate()

    if let token = timeObserverToken {
      player.removeTimeObserver(token)
    }

    statusObserverToken?.invalidate()
    bufferingObserverToken?.invalidate()
    playingObserverToken?.invalidate()

    cancellables.removeAll()

    player.replaceCurrentItem(with: nil)
  }

  // MARK: - Controls Auto-Hide

  /// Show controls and start auto-hide timer
  public func showControlsWithAutoHide() {
    showControls = true
    resetControlsHideTimer()
  }

  /// Toggle controls visibility
  public func toggleControls() {
    showControls.toggle()
    if showControls {
      resetControlsHideTimer()
    } else {
      controlsHideTimer?.invalidate()
      controlsHideTimer = nil
    }
  }

  private func resetControlsHideTimer() {
    controlsHideTimer?.invalidate()

    controlsHideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
      DispatchQueue.main.async {
        self?.showControls = false
      }
    }
  }
}
