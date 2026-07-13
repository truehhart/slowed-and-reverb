import Foundation

nonisolated struct LibrarySong: Identifiable, Equatable, Sendable {
  let track: Track
  let addedAt: Date

  var id: String { track.id }
}
