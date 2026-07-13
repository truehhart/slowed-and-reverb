import Foundation

nonisolated struct LibrarySnapshot: Equatable, Sendable {
  let songs: [LibrarySong]
  let playlists: [LibraryPlaylist]

  static let empty = LibrarySnapshot(songs: [], playlists: [])
}
