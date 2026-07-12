import Foundation

/// PlayerModel implements this to receive OS media-key / Control Center commands.
/// Replaces the old souvlaki + `media-key` event plumbing.
protocol NowPlayingDelegate: AnyObject {
  func nowPlayingDidRequestPlay()
  func nowPlayingDidRequestPause()
  func nowPlayingDidRequestTogglePlayPause()
  func nowPlayingDidRequestNext()
  func nowPlayingDidRequestPrevious()
  func nowPlayingDidRequestSeek(to time: TimeInterval)
  func nowPlayingDidRequestSkip(by delta: TimeInterval)
}
