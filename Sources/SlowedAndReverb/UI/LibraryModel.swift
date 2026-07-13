import Foundation
import Observation

@MainActor
@Observable
final class LibraryModel {
  enum Section: String, CaseIterable {
    case songs
    case playlists
  }

  enum SongSort: String, CaseIterable {
    case dateAdded = "date added"
    case title
    case artist
  }

  enum PlaylistSort: String, CaseIterable {
    case dateAdded = "date added"
    case name
  }

  private(set) var snapshot = LibrarySnapshot.empty
  private(set) var isLoading = false
  private(set) var errorMessage: String?
  var section = Section.songs
  var query = ""
  var songSort = SongSort.dateAdded {
    didSet { isAscending = songSort != .dateAdded }
  }
  var playlistSort = PlaylistSort.dateAdded {
    didSet { isAscending = playlistSort != .dateAdded }
  }
  var isAscending = false
  var selectedPlaylistID: String?

  var selectedPlaylist: LibraryPlaylist? {
    snapshot.playlists.first { $0.id == selectedPlaylistID }
  }

  var songs: [LibrarySong] {
    let matching = snapshot.songs.filter { song in
      query.isEmpty || Self.matches(query, in: [song.track.title, song.track.artist])
    }
    return matching.sorted(by: compareSongs)
  }

  var playlists: [LibraryPlaylist] {
    let matching = snapshot.playlists.filter { playlist in
      query.isEmpty
        || Self.matches(
          query,
          in: [playlist.title]
            + playlist.tracks.flatMap { [$0.title, $0.artist].compactMap { $0 } })
    }
    return matching.sorted(by: comparePlaylists)
  }

  var selectedPlaylistTracks: [Track] {
    guard let selectedPlaylist else { return [] }
    return selectedPlaylist.tracks.filter { track in
      query.isEmpty || Self.matches(query, in: [track.title, track.artist])
    }
  }

  func load(using player: PlayerModel) async {
    isLoading = true
    errorMessage = nil
    snapshot = await player.librarySnapshot()
    if selectedPlaylistID != nil, selectedPlaylist == nil { selectedPlaylistID = nil }
    isLoading = false
  }

  func removeSong(id: String, using player: PlayerModel) async -> Bool {
    do {
      try await player.removeLibrarySong(id: id)
      await load(using: player)
      return true
    } catch {
      errorMessage = String(describing: error)
      return false
    }
  }

  func removePlaylist(id: String, using player: PlayerModel) async -> Bool {
    do {
      try await player.removeLibraryPlaylist(id: id)
      selectedPlaylistID = nil
      await load(using: player)
      return true
    } catch {
      errorMessage = String(describing: error)
      return false
    }
  }

  nonisolated static func matches(_ query: String, in values: [String?]) -> Bool {
    let needle = normalized(query)
    guard !needle.isEmpty else { return true }
    return values.compactMap { $0 }.contains { normalized($0).contains(needle) }
  }

  private nonisolated static func normalized(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
  }

  private func compareSongs(_ lhs: LibrarySong, _ rhs: LibrarySong) -> Bool {
    let comparison: ComparisonResult
    switch songSort {
    case .dateAdded:
      comparison = lhs.addedAt.compare(rhs.addedAt)
    case .title:
      comparison = textCompare(lhs.track.title, rhs.track.title)
    case .artist:
      comparison = textCompare(lhs.track.artist ?? "", rhs.track.artist ?? "")
    }
    if comparison != .orderedSame {
      return isAscending ? comparison == .orderedAscending : comparison == .orderedDescending
    }
    let titleComparison = textCompare(lhs.track.title, rhs.track.title)
    if titleComparison != .orderedSame { return titleComparison == .orderedAscending }
    return lhs.id < rhs.id
  }

  private func comparePlaylists(_ lhs: LibraryPlaylist, _ rhs: LibraryPlaylist) -> Bool {
    let comparison =
      playlistSort == .dateAdded
      ? lhs.addedAt.compare(rhs.addedAt) : textCompare(lhs.title, rhs.title)
    if comparison != .orderedSame {
      return isAscending ? comparison == .orderedAscending : comparison == .orderedDescending
    }
    let nameComparison = textCompare(lhs.title, rhs.title)
    if nameComparison != .orderedSame { return nameComparison == .orderedAscending }
    return lhs.id < rhs.id
  }

  private func textCompare(_ lhs: String, _ rhs: String) -> ComparisonResult {
    lhs.localizedCaseInsensitiveCompare(rhs)
  }
}
