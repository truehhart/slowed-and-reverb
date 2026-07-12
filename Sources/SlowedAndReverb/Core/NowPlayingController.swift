import AppKit
import Foundation
@preconcurrency import MediaPlayer

/// Wraps MPNowPlayingInfoCenter + MPRemoteCommandCenter. Elapsed/duration are
/// real seconds; playbackRate is the actual speed while playing (0 when
/// paused), so Control Center interpolates the scrubber natively.
final class NowPlayingController {
  weak var delegate: NowPlayingDelegate?

  private let commandCenter = MPRemoteCommandCenter.shared()
  private let infoCenter = MPNowPlayingInfoCenter.default()
  private nonisolated(unsafe) var commandTargets: [(MPRemoteCommand, Any)] = []
  private var artworkTrackID: String?
  private var artworkFetch: Task<Void, Never>?

  static let skipInterval: TimeInterval = 5

  init() {
    register(commandCenter.playCommand) { [weak self] _ in
      self?.delegate?.nowPlayingDidRequestPlay()
      return .success
    }
    register(commandCenter.pauseCommand) { [weak self] _ in
      self?.delegate?.nowPlayingDidRequestPause()
      return .success
    }
    register(commandCenter.togglePlayPauseCommand) { [weak self] _ in
      self?.delegate?.nowPlayingDidRequestTogglePlayPause()
      return .success
    }
    register(commandCenter.nextTrackCommand) { [weak self] _ in
      self?.delegate?.nowPlayingDidRequestNext()
      return .success
    }
    register(commandCenter.previousTrackCommand) { [weak self] _ in
      self?.delegate?.nowPlayingDidRequestPrevious()
      return .success
    }
    commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
    register(commandCenter.skipForwardCommand) { [weak self] _ in
      self?.delegate?.nowPlayingDidRequestSkip(by: Self.skipInterval)
      return .success
    }
    commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
    register(commandCenter.skipBackwardCommand) { [weak self] _ in
      self?.delegate?.nowPlayingDidRequestSkip(by: -Self.skipInterval)
      return .success
    }
    register(commandCenter.changePlaybackPositionCommand) { [weak self] event in
      guard let event = event as? MPChangePlaybackPositionCommandEvent else {
        return .commandFailed
      }
      self?.delegate?.nowPlayingDidRequestSeek(to: event.positionTime)
      return .success
    }
  }

  deinit {
    for (command, target) in commandTargets {
      command.removeTarget(target)
    }
  }

  private func register(
    _ command: MPRemoteCommand,
    handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
  ) {
    commandTargets.append((command, command.addTarget(handler: handler)))
  }

  /// Full metadata rebuild (title/duration/artwork): call on track change.
  func setTrack(
    _ track: Track?, artworkURL: URL?, duration: TimeInterval, elapsed: TimeInterval, speed: Double,
    isPlaying: Bool
  ) {
    guard let track else {
      clear()
      return
    }
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: track.title,
      MPMediaItemPropertyPlaybackDuration: duration,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
      MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? speed : 0,
    ]
    if let artwork = infoCenter.nowPlayingInfo?[MPMediaItemPropertyArtwork],
      artworkTrackID == track.id
    {
      info[MPMediaItemPropertyArtwork] = artwork
    }
    infoCenter.nowPlayingInfo = info
    infoCenter.playbackState = isPlaying ? .playing : .paused

    if artworkTrackID != track.id {
      artworkTrackID = track.id
      artworkFetch?.cancel()
      if let artworkURL {
        artworkFetch = Task { [weak self] in
          await self?.loadArtwork(from: artworkURL, trackID: track.id)
        }
      }
    }
  }

  /// Lightweight tick: position/rate/state only, no metadata dict rebuild
  /// (which would re-load artwork). Call on seek/speed-change/status-change.
  func updatePosition(elapsed: TimeInterval, speed: Double, isPlaying: Bool) {
    guard var info = infoCenter.nowPlayingInfo else { return }
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
    info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? speed : 0
    infoCenter.nowPlayingInfo = info
    infoCenter.playbackState = isPlaying ? .playing : .paused
  }

  func clear() {
    artworkFetch?.cancel()
    artworkTrackID = nil
    infoCenter.nowPlayingInfo = nil
    infoCenter.playbackState = .stopped
  }

  private func loadArtwork(from url: URL, trackID: String) async {
    // The cover is a local cache file; read it off the main actor so a slow
    // disk hit never stalls the UI. Decode back on the main actor.
    guard
      let data = try? await Task.detached(
        priority: .utility, operation: { try Data(contentsOf: url) }
      )
      .value,
      let image = NSImage(data: data)
    else { return }
    guard artworkTrackID == trackID else { return }  // superseded while loading
    var info = infoCenter.nowPlayingInfo ?? [:]
    info[MPMediaItemPropertyArtwork] = Self.artwork(for: image)
    infoCenter.nowPlayingInfo = info
  }

  /// MediaPlayer calls the artwork request handler on an arbitrary queue, so it
  /// must be nonisolated; a MainActor-isolated handler trips the executor
  /// assertion and crashes when Control Center renders the cover.
  nonisolated private static func artwork(for image: NSImage) -> MPMediaItemArtwork {
    MPMediaItemArtwork(boundsSize: image.size) { _ in image }
  }
}
