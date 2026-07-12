import Foundation

nonisolated struct Track: Identifiable, Equatable, Sendable {
  let id: String
  var title: String
  var artist: String?
  let webpageURL: URL
  let thumbnailURL: URL?
  let duration: TimeInterval?

  init(
    id: String, title: String, artist: String? = nil, webpageURL: URL, thumbnailURL: URL?,
    duration: TimeInterval? = nil
  ) {
    self.id = id
    self.title = title
    self.artist = artist
    self.webpageURL = webpageURL
    self.thumbnailURL = thumbnailURL
    self.duration = duration
  }
}
