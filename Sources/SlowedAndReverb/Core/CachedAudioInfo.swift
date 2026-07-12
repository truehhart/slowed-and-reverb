import Foundation

nonisolated struct CachedAudioInfo: Sendable, Equatable {
  let path: URL
  let id: String
  let title: String?
  let artist: String?
  let webpageURL: URL?
  let thumbnailURL: URL?
  let duration: TimeInterval?

  init(
    path: URL, id: String, title: String?, artist: String? = nil, webpageURL: URL?,
    thumbnailURL: URL?, duration: TimeInterval?
  ) {
    self.path = path
    self.id = id
    self.title = title
    self.artist = artist
    self.webpageURL = webpageURL
    self.thumbnailURL = thumbnailURL
    self.duration = duration
  }
}
