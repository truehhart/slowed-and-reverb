import Foundation

nonisolated struct CachedAudioInfo: Sendable, Equatable {
  let path: URL
  let title: String?
}
