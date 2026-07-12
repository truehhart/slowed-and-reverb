import Foundation

@testable import SlowedAndReverb

/// AudioEngineProtocol fake: PlayerModel's queue/token/repeat logic is
/// exercised without any real audio hardware or AVFoundation involvement.
@MainActor
final class FakeAudioEngine: AudioEngineProtocol {
  var currentTime: TimeInterval = 0
  var duration: TimeInterval = 0
  private(set) var hasSource = false
  private(set) var paused = false

  var speed: Double = 0.85
  var reverbMix: Double = 0.6
  var reverbSpace: ReverbSpace = .hall
  var reverbCutoff: Double = 80
  var volume: Double = 1
  var isMuted: Bool = false

  var onEnded: (() -> Void)?

  /// Test knobs.
  var playError: Error?
  var restartSucceeds = true
  var playedURLs: [URL] = []
  var stopCallCount = 0
  var restartCallCount = 0

  func play(fileURL: URL, startAt: TimeInterval) throws {
    if let playError {
      hasSource = false
      throw playError
    }
    playedURLs.append(fileURL)
    hasSource = true
    paused = false
    currentTime = startAt
    duration = 100
  }

  func stop() async {
    stopCallCount += 1
    hasSource = false
    paused = false
  }

  @discardableResult
  func togglePause() async -> Bool {
    guard hasSource else { return false }
    paused.toggle()
    return paused
  }

  @discardableResult
  func restart() async -> Bool {
    restartCallCount += 1
    guard restartSucceeds else { return false }
    hasSource = true
    paused = false
    currentTime = 0
    return true
  }

  func seek(to time: TimeInterval) async {
    currentTime = time
  }

  func levels() -> (l: Float, r: Float) { (0, 0) }
}
