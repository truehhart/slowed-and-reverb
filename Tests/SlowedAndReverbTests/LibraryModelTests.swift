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

  @Test func staysInInitialLoadingStateUntilTheFirstSnapshotArrives() async {
    let model = LibraryModel()

    #expect(model.isLoading)
    #expect(!model.hasLoaded)

    await model.load(
      using: PlayerModel(ytdlp: FakeYtDlpClient(), audioEngine: FakeAudioEngine()))

    #expect(!model.isLoading)
    #expect(model.hasLoaded)
  }

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
    model.songSortAscending = true
    #expect(model.songs.map(\.id) == ["a", "b", "c"])

    model.songSort = .title
    #expect(model.songSortAscending)
    #expect(model.songs.map(\.id) == ["b", "a", "c"])
    model.songSortAscending = false
    #expect(model.songs.map(\.id) == ["c", "a", "b"])

    model.songSort = .artist
    #expect(model.songs.map(\.id) == ["c", "b", "a"])
    model.songSortAscending = false
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
    model.playlistSortAscending = false
    #expect(model.playlists.map(\.id) == ["playlist-b", "playlist-a"])

    model.selectedPlaylistID = "playlist-a"
    #expect(model.selectedPlaylistSongs.map(\.id) == ["c", "a"])
    model.query = "ete"
    #expect(model.selectedPlaylistSongs.map(\.id) == ["a"])
  }

  @Test func keepsSongAndPlaylistSortDirectionsIndependent() async {
    let model = await populatedModel()

    model.songSort = .title
    model.songSortAscending = false
    model.section = .playlists
    model.playlistSort = .name

    #expect(model.songSortAscending == false)
    #expect(model.playlistSortAscending == true)

    model.playlistSortAscending = false
    model.section = .songs
    #expect(model.songSortAscending == false)
  }

  @Test func defaultsBothSectionsToNewestFirst() async {
    let model = await populatedModel()

    #expect(model.songSort == .dateAdded)
    #expect(model.songSortAscending == false)
    #expect(model.songs.map(\.id) == ["b", "c", "a"])
    #expect(model.playlistSort == .dateAdded)
    #expect(model.playlistSortAscending == false)
    #expect(model.playlists.map(\.id) == ["playlist-b", "playlist-a"])
  }

  @Test func formatsRelativeAddedDatesAtDayBoundaries() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = Date(timeIntervalSince1970: 1_768_089_600)
    let locale = Locale(identifier: "en_US")

    func label(daysAgo: Int) -> String {
      let date = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
      return LibraryModel.addedDateLabel(
        for: date, now: now, calendar: calendar, locale: locale)
    }

    #expect(label(daysAgo: 0) == "Added Today")
    #expect(label(daysAgo: 1) == "Added Yesterday")
    #expect(label(daysAgo: 2) == "Added 2d ago")
    #expect(label(daysAgo: 6) == "Added 6d ago")
    #expect(label(daysAgo: 7) == "Added 1w ago")
    #expect(label(daysAgo: 13) == "Added 1w ago")
    #expect(label(daysAgo: 14) == "Added 12/28/25")
  }

  @Test func presentsPlaylistTracksMissingFromTheSongLibrary() async {
    let model = LibraryModel()
    let ytdlp = FakeYtDlpClient()
    let track = Track(
      id: "playlist-only", title: "Playlist Only", artist: "Artist",
      webpageURL: URL(string: "https://example.test/playlist-only")!, thumbnailURL: nil)
    ytdlp.snapshot = LibrarySnapshot(
      songs: [],
      playlists: [
        LibraryPlaylist(
          id: "playlist", title: "Playlist", sourceURL: URL(string: "https://x/playlist")!,
          addedAt: old, tracks: [track])
      ])
    await model.load(using: PlayerModel(ytdlp: ytdlp, audioEngine: FakeAudioEngine()))
    model.selectedPlaylistID = "playlist"

    #expect(model.selectedPlaylistSongs == [LibrarySong(track: track, addedAt: old)])
  }

  @Test func refreshesSnapshotAfterRemovingSong() async {
    let model = LibraryModel()
    let ytdlp = FakeYtDlpClient()
    let song = librarySong("only", title: "Only", addedAt: old)
    ytdlp.snapshot = LibrarySnapshot(songs: [song], playlists: [])
    let player = PlayerModel(ytdlp: ytdlp, audioEngine: FakeAudioEngine())
    await model.load(using: player)

    #expect(await model.removeSong(id: song.id, using: player))
    #expect(model.snapshot.songs.isEmpty)
  }

  @Test func leavesPlaylistSelectedWhenRemovalFails() async {
    struct RemovalError: Error {}

    let model = LibraryModel()
    let ytdlp = FakeYtDlpClient()
    ytdlp.removePlaylistError = RemovalError()
    ytdlp.snapshot = LibrarySnapshot(
      songs: [],
      playlists: [
        LibraryPlaylist(
          id: "playlist", title: "Playlist", sourceURL: URL(string: "https://x/playlist")!,
          addedAt: old, tracks: [])
      ])
    let player = PlayerModel(ytdlp: ytdlp, audioEngine: FakeAudioEngine())
    await model.load(using: player)
    model.selectedPlaylistID = "playlist"

    #expect(await model.removePlaylist(id: "playlist", using: player) == false)
    #expect(model.selectedPlaylistID == "playlist")
    #expect(model.errorMessage == nil)
    #expect(model.playlists.map(\.id) == ["playlist"])
  }

  @Test func clearsSelectionAndRefreshesSnapshotAfterRemovingPlaylist() async {
    let model = LibraryModel()
    let ytdlp = FakeYtDlpClient()
    ytdlp.snapshot = LibrarySnapshot(
      songs: [],
      playlists: [
        LibraryPlaylist(
          id: "playlist", title: "Playlist", sourceURL: URL(string: "https://x/playlist")!,
          addedAt: old, tracks: [])
      ])
    let player = PlayerModel(ytdlp: ytdlp, audioEngine: FakeAudioEngine())
    await model.load(using: player)
    model.selectedPlaylistID = "playlist"

    #expect(await model.removePlaylist(id: "playlist", using: player))
    #expect(model.selectedPlaylistID == nil)
    #expect(model.snapshot.playlists.isEmpty)
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
