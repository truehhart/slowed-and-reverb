import Foundation

nonisolated struct LibraryPlaylist: Identifiable, Equatable, Sendable {
  let id: String
  let title: String
  let sourceURL: URL
  let addedAt: Date
  let tracks: [Track]
}
