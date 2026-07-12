import Foundation

/// Seam between PlayerModel and AVFoundation so playback logic (token
/// supersede, failure skip, lookahead...) is testable without real audio
/// hardware. AVFoundationAudioEngine is the production conformer.
@MainActor
protocol AudioEngineProtocol: AnyObject {
  /// Position in the *source track's* timeline, seconds (see PlayerModel.currentTime).
  var currentTime: TimeInterval { get }
  var duration: TimeInterval { get }

  var speed: Double { get set }
  var reverbMix: Double { get set }
  var reverbSpace: ReverbSpace { get set }
  var reverbCutoff: Double { get set }
  var volume: Double { get set }
  var isMuted: Bool { get set }

  /// Fires exactly once per natural end-of-track; never for stop/seek/restart.
  var onEnded: (() -> Void)? { get set }

  /// Load and play `fileURL` from `startAt` seconds (clamped to duration).
  func play(fileURL: URL, startAt: TimeInterval) throws

  /// Stop immediately without firing `onEnded`.
  func stop()

  /// Returns true if now paused.
  @discardableResult
  func togglePause() -> Bool

  /// Restart the current track from 0. Returns false if nothing is loaded.
  @discardableResult
  func restart() -> Bool

  /// Seek, preserving paused/playing state. No-op if nothing is loaded.
  func seek(to time: TimeInterval)

  func levels() -> (l: Float, r: Float)
}
