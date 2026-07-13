import Foundation
import Testing

@testable import SlowedAndReverb

private func librarySong(
  _ id: String, title: String, artist: String? = nil, addedAt: Date
) -> LibrarySong {
  LibrarySong(
    track: Track(
      id: id, title: title, artist: artist,
      webpageURL: URL(string: "https://example.test/\(id)")!, thumbnailURL: nil),
    addedAt: addedAt)
}

@Suite struct LibraryModelTests {
  private let old = Date(timeIntervalSince1970: 100)
  private let recent = Date(timeIntervalSince1970: 200)

  @Test func searchIgnoresCaseAndDiacriticsAcrossTitleAndArtist() async {
    let model = await populatedModel()

    model.query = "BEYONCE"
    #expect(model.songs.map(\.id) == ["b"])
    model.query = "ete"
    #expect(model.songs.map(\.id) == ["a"])
  }

  @Test func sortsSongsByEveryFieldAndDirectionWithDeterministicTies() async {
    let model = await populatedModel()

    #expect(model.songs.map(\.id) == ["b", "c", "a"])
    model.isAscending = true
    #expect(model.songs.map(\.id) == ["a", "b", "c"])

    model.songSort = .title
    #expect(model.isAscending)
    #expect(model.songs.map(\.id) == ["b", "a", "c"])
    model.isAscending = false
    #expect(model.songs.map(\.id) == ["c", "a", "b"])

    model.songSort = .artist
    #expect(model.songs.map(\.id) == ["c", "b", "a"])
    model.isAscending = false
    #expect(model.songs.map(\.id) == ["a", "b", "c"])
  }

  @Test func titleAndIDBreakEqualSortValues() async {
    let model = LibraryModel()
    let ytdlp = FakeYtDlpClient()
    let engine = FakeAudioEngine()
    let date = Date()
    ytdlp.snapshot = LibrarySnapshot(
      songs: [
        librarySong("b", title: "Same", artist: "Artist", addedAt: date),
        librarySong("a", title: "Same", artist: "Artist", addedAt: date),
        librarySong("c", title: "Alpha", artist: "Artist", addedAt: date),
      ], playlists: [])
    await model.load(using: PlayerModel(ytdlp: ytdlp, audioEngine: engine))
    model.songSort = .artist

    #expect(model.songs.map(\.id) == ["c", "a", "b"])
  }

  @Test func searchesAndSortsPlaylistsAndPreservesDetailOrder() async {
    let model = await populatedModel()
    model.section = .playlists
    model.query = "beyonce"
    #expect(model.playlists.map(\.id) == ["playlist-b"])

    model.query = ""
    model.playlistSort = .name
    #expect(model.playlists.map(\.id) == ["playlist-a", "playlist-b"])
    model.isAscending = false
    #expect(model.playlists.map(\.id) == ["playlist-b", "playlist-a"])

    model.selectedPlaylistID = "playlist-a"
    #expect(model.selectedPlaylistTracks.map(\.id) == ["c", "a"])
    model.query = "ete"
    #expect(model.selectedPlaylistTracks.map(\.id) == ["a"])
  }

  @Test func refreshesSnapshotAfterRemoval() async {
    let model = await populatedModel()
    let ytdlp = FakeYtDlpClient()
    let song = librarySong("only", title: "Only", addedAt: old)
    ytdlp.snapshot = LibrarySnapshot(songs: [song], playlists: [])
    let player = PlayerModel(ytdlp: ytdlp, audioEngine: FakeAudioEngine())
    await model.load(using: player)

    #expect(await model.removeSong(id: song.id, using: player))
    #expect(model.snapshot.songs.isEmpty)
  }

  private func populatedModel() async -> LibraryModel {
    let model = LibraryModel()
    let ytdlp = FakeYtDlpClient()
    let songs = [
      librarySong("a", title: "Été", artist: "Zoë", addedAt: old),
      librarySong("b", title: "Alpha", artist: "Beyoncé", addedAt: recent),
      librarySong("c", title: "Zulu", addedAt: recent),
    ]
    ytdlp.snapshot = LibrarySnapshot(
      songs: songs,
      playlists: [
        LibraryPlaylist(
          id: "playlist-a", title: "Ambient", sourceURL: URL(string: "https://x/a")!,
          addedAt: old, tracks: [songs[2].track, songs[0].track]),
        LibraryPlaylist(
          id: "playlist-b", title: "Night", sourceURL: URL(string: "https://x/b")!,
          addedAt: recent, tracks: [songs[1].track]),
      ])
    await model.load(using: PlayerModel(ytdlp: ytdlp, audioEngine: FakeAudioEngine()))
    return model
  }
}
