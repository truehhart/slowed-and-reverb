import Foundation

@testable import SlowedAndReverb

/// YtDlpClientProtocol fake, driven entirely by MainActor test code (no real
/// process/network), so PlayerModel's queue logic is testable without yt-dlp.
final class FakeYtDlpClient: YtDlpClientProtocol, @unchecked Sendable {
  var resolveHandler: ((String) throws -> [Track])?
  var asyncResolveHandler: ((String) async throws -> [Track])?
  var metadataUpdates: AsyncStream<Track>?
  var downloadHandler: ((String, String) async throws -> URL)?
  var downloadProgressValues: [Double] = []
  var cachedAudioByID: [String: CachedAudioInfo] = [:]
  var cachedAudioByURL: [String: CachedAudioInfo] = [:]
  var snapshot = LibrarySnapshot.empty
  var removeSongError: (any Error)?
  var removePlaylistError: (any Error)?

  private(set) var resolveCalls: [String] = []
  private(set) var downloadCalls: [(url: String, id: String)] = []
  private(set) var cancelCount = 0
  private(set) var removedSongIDs: [String] = []
  private(set) var removedPlaylistIDs: [String] = []

  func resolve(url: String) async throws -> ResolvedTracks {
    resolveCalls.append(url)
    let tracks: [Track]
    if let asyncResolveHandler {
      tracks = try await asyncResolveHandler(url)
    } else if let resolveHandler {
      tracks = try resolveHandler(url)
    } else {
      tracks = []
    }
    guard let metadataUpdates else { return ResolvedTracks(tracks: tracks) }
    return ResolvedTracks(tracks: tracks, metadataUpdates: metadataUpdates)
  }

  func download(url: String, id: String, progress: @escaping @Sendable (Double) async -> Void)
    async throws -> URL
  {
    downloadCalls.append((url, id))
    for value in downloadProgressValues {
      await progress(value)
    }
    guard let downloadHandler else {
      return URL(fileURLWithPath: "/cache/\(id).m4a")
    }
    return try await downloadHandler(url, id)
  }

  func cancelActiveDownload() async {
    cancelCount += 1
  }

  func cachedAudio(id: String) async -> CachedAudioInfo? {
    cachedAudioByID[id]
  }

  func cachedAudio(url: String) async -> CachedAudioInfo? {
    cachedAudioByURL[url]
  }

  func librarySnapshot() async -> LibrarySnapshot { snapshot }

  func removeLibrarySong(id: String) async throws {
    if let removeSongError { throw removeSongError }
    removedSongIDs.append(id)
    snapshot = LibrarySnapshot(
      songs: snapshot.songs.filter { $0.id != id },
      playlists: snapshot.playlists.map { playlist in
        LibraryPlaylist(
          id: playlist.id, title: playlist.title, sourceURL: playlist.sourceURL,
          addedAt: playlist.addedAt, tracks: playlist.tracks.filter { $0.id != id })
      })
  }

  func removeLibraryPlaylist(id: String) async throws {
    if let removePlaylistError { throw removePlaylistError }
    removedPlaylistIDs.append(id)
    snapshot = LibrarySnapshot(
      songs: snapshot.songs, playlists: snapshot.playlists.filter { $0.id != id })
  }
  func artworkURL(for track: Track) async -> URL? { nil }
  func cacheSize() async -> UInt64 { 0 }
  func purgeCache() async throws {}
}

/// Polls `condition` until it's true or `timeout` elapses. Swift Testing has
/// no `vi.waitFor` equivalent; background Tasks (lookahead preload) need a
/// few scheduler turns before their effects are observable.
func waitUntil(timeout: Duration = .seconds(2), _ condition: @autoclosure () -> Bool) async {
  let deadline = ContinuousClock.now + timeout
  while !condition(), ContinuousClock.now < deadline {
    try? await Task.sleep(for: .milliseconds(5))
  }
}
