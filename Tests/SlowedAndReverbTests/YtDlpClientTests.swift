import CoreData
import Foundation
import Testing

@testable import SlowedAndReverb

/// Foundation's `resolvingSymlinksInPath` won't resolve `/var` ->
/// `/private/var` for a not-yet-existing path; `contentsOfDirectory` does,
/// so canonicalize fixtures with realpath(3) to match.
private func canonical(_ url: URL) -> URL {
  var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
  guard realpath(url.path, &buffer) != nil else { return url }
  let length = buffer.firstIndex(of: 0) ?? buffer.count
  return URL(
    fileURLWithPath: String(
      decoding: buffer[..<length].map { UInt8(bitPattern: $0) }, as: UTF8.self))
}

@Suite struct PercentParsingTests {
  @Test func readsYtDlpProgressLines() {
    #expect(YtDlpClient.parsePercent("[download]  12.3% of 4.00MiB at 1.00MiB/s") == 12.3)
    #expect(YtDlpClient.parsePercent("[download] 100% of 4.00MiB") == 100.0)
    #expect(YtDlpClient.parsePercent("ERROR: video unavailable") == nil)
  }
}

@Suite struct UnavailableTitleTests {
  @Test func flagsBracketedPlaceholders() {
    #expect(YtDlpClient.isUnavailableTitle("[Private video]"))
    #expect(YtDlpClient.isUnavailableTitle("[Deleted video]"))
    #expect(YtDlpClient.isUnavailableTitle("[Unavailable video]"))
    #expect(YtDlpClient.isUnavailableTitle("[UNAVAILABLE]"))
    #expect(!YtDlpClient.isUnavailableTitle("Real Song"))
    #expect(!YtDlpClient.isUnavailableTitle("[Official Video]"))
  }
}

@Suite struct FlatPlaylistEntryParsingTests {
  @Test func usesDefaultsForSparseEntries() {
    let track = YtDlpClient.parseTrack(
      .init(
        id: "aaaaaaaaaaa", title: "Sparse",
        thumbnails: [
          .init(url: "https://img.example/small.jpg"), .init(url: "https://img.example/large.jpg"),
        ]))

    #expect(track?.id == "aaaaaaaaaaa")
    #expect(track?.title == "Sparse")
    #expect(track?.webpageURL.absoluteString == "https://www.youtube.com/watch?v=aaaaaaaaaaa")
    #expect(track?.thumbnailURL?.absoluteString == "https://img.example/large.jpg")
  }

  @Test func preservesAnExplicitWebpageURL() {
    let track = YtDlpClient.parseTrack(
      .init(
        id: "aaaaaaaaaaa", title: "Explicit", webpageURL: "https://example.test/watch",
        thumbnail: "https://img.example/direct.jpg"))

    #expect(track?.webpageURL.absoluteString == "https://example.test/watch")
    #expect(track?.thumbnailURL?.absoluteString == "https://img.example/direct.jpg")
  }

  @Test func infersArtistFromMetadataTitleAndChannel() {
    let explicit = YtDlpClient.parseTrack(
      .init(id: "a", title: "Wrong - Song", artist: "  Metadata Artist  ", channel: "Channel"))
    #expect(explicit?.artist == "Metadata Artist")
    #expect(explicit?.title == "Wrong - Song")

    let inferred = YtDlpClient.parseTrack(.init(id: "b", title: "Title Artist - Song"))
    #expect(inferred?.artist == "Title Artist")
    #expect(inferred?.title == "Song")
    #expect(
      YtDlpClient.parseTrack(
        .init(id: "c", title: "Song Without Artist", channel: "Artist - Topic"))?
        .artist == "Artist")
    #expect(YtDlpClient.parseTrack(.init(id: "d", title: "AC-DC Song"))?.artist == nil)
    #expect(
      YtDlpClient.parseTrack(.init(id: "e", title: "Official Video - Song", channel: "Fallback"))?
        .artist == "Fallback")
  }

  @Test func skipsUnplayableEntries() {
    #expect(YtDlpClient.parseTrack(.init(title: "No id")) == nil)
    #expect(
      YtDlpClient.parseTrack(.init(id: "bbbbbbbbbbb", webpageURL: "https://example.test/watch"))
        == nil)  // no title
    #expect(YtDlpClient.parseTrack(.init(id: "ddddddddddd", title: "[Private video]")) == nil)
    #expect(YtDlpClient.parseTrack(.init(id: "eeeeeeeeeee", title: "[Deleted video]")) == nil)

    let track = YtDlpClient.parseTrack(.init(id: "fffffffffff", title: "Real Song"))
    #expect(track?.title == "Real Song")
  }

  /// End-to-end decode of a `-J --flat-playlist` payload: entries split,
  /// unavailable titles dropped, malformed entries (null, wrong types)
  /// skipped without failing the playlist, thumbnail taken as the last of
  /// the array, explicit webpage_url preserved.
  @Test func decodesFlatPlaylistJSON() throws {
    let json = """
      {"entries":[
        {"id":"aaaaaaaaaaa","title":"One"},
        {"id":"bbbbbbbbbbb","title":"[Private video]"},
        null,
        {"id":12345,"title":"Numeric id from an odd extractor"},
        {"id":"ccccccccccc","title":"Two","webpage_url":"https://x.test/w",
         "thumbnails":[{"url":"https://t/1.jpg"},{"url":"https://t/2.jpg"}]}
      ]}
      """
    let root = try JSONDecoder().decode(YtDlpClient.RawEntry.self, from: Data(json.utf8))
    let entries = root.entries.map { $0.compactMap(\.value) } ?? [root]
    let tracks = entries.compactMap(YtDlpClient.parseTrack)

    #expect(tracks.count == 2)
    #expect(tracks[0].id == "aaaaaaaaaaa")
    #expect(tracks[1].webpageURL.absoluteString == "https://x.test/w")
    #expect(tracks[1].thumbnailURL?.absoluteString == "https://t/2.jpg")
  }
}

@Suite struct PlaylistMetadataEnrichmentTests {
  @Test func resolvesFullMetadataAndPreservesPlaylistOrder() async throws {
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/fake-ytdlp.nu")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ytdlp-enrichment-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let client = YtDlpClient(
      binaryURL: fixture, cacheDir: root.appendingPathComponent("cache"),
      libraryURL: root.appendingPathComponent("Library.store"))

    let tracks = try await client.resolve(url: "https://example.test/playlist")

    #expect(tracks.map(\.id) == ["aaaaaaaaaaa", "bbbbbbbbbbb"])
    #expect(tracks.map(\.title) == ["One", "Two"])
    #expect(tracks.map(\.artist) == ["Artist A", "Artist B"])
    #expect(tracks.map(\.duration) == [123, 234])
    let playlist = await client.librarySnapshot().playlists.first
    #expect(playlist?.tracks.map(\.artist) == ["Artist A", "Artist B"])
  }
}

@Suite struct CacheScanAndMetaRoundTripTests {
  @Test func findsCachedAudioAndRoundTripsTitleMetadata() async throws {
    let unresolved = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ytdlp-cache-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: unresolved, withIntermediateDirectories: true)
    let dir = canonical(unresolved)
    defer { try? FileManager.default.removeItem(at: unresolved) }

    let audioPath = dir.appendingPathComponent("ccccccccccc.m4a")
    try Data("audio".utf8).write(to: audioPath)
    // A decoy .json with a non-metadata payload must never be picked as the audio file.
    try Data("not the audio".utf8).write(to: dir.appendingPathComponent("ccccccccccc.json"))
    try JSONSerialization.data(withJSONObject: ["title": "Cached Title"])
      .write(to: dir.appendingPathComponent("ccccccccccc.json"))
    let client = YtDlpClient(
      binaryURL: URL(fileURLWithPath: "/usr/bin/true"), cacheDir: dir,
      libraryURL: dir.appendingPathComponent("support/Library.sqlite"))

    let cached = await client.cachedAudio(id: "ccccccccccc")
    #expect(cached?.path == audioPath)
    #expect(cached?.id == "ccccccccccc")
    #expect(cached?.title == "Cached Title")

    #expect(await client.cachedAudio(id: "not-cached-id") == nil)
  }

  @Test func findsCachedAudioByStoredWebpageURL() async throws {
    let unresolved = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ytdlp-cache-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: unresolved, withIntermediateDirectories: true)
    let dir = canonical(unresolved)
    defer { try? FileManager.default.removeItem(at: unresolved) }

    let id = "soundcloud-track"
    let webpageURL = "https://soundcloud.com/artist/song"
    let audioPath = dir.appendingPathComponent("\(id).m4a")
    try Data("audio".utf8).write(to: audioPath)
    try JSONSerialization.data(
      withJSONObject: ["title": "Cached Song", "webpageURL": webpageURL]
    ).write(to: dir.appendingPathComponent("\(id).json"))
    let client = YtDlpClient(
      binaryURL: URL(fileURLWithPath: "/usr/bin/true"), cacheDir: dir,
      libraryURL: dir.appendingPathComponent("support/Library.sqlite"))

    let cached = await client.cachedAudio(url: webpageURL)
    #expect(cached?.path == audioPath)
    #expect(cached?.id == id)
    #expect(cached?.title == "Cached Song")
    #expect(cached?.webpageURL?.absoluteString == webpageURL)
    #expect(await client.cachedAudio(url: "https://soundcloud.com/artist/other") == nil)
  }

  @Test func cacheSizeSumsTopLevelFilesOnly() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ytdlp-cache-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let client = YtDlpClient(
      binaryURL: URL(fileURLWithPath: "/usr/bin/true"), cacheDir: dir,
      libraryURL: dir.appendingPathComponent("support/Library.sqlite"))
    try Data(repeating: 0, count: 10).write(to: dir.appendingPathComponent("a.m4a"))
    try Data(repeating: 0, count: 20).write(to: dir.appendingPathComponent("b.m4a"))

    #expect(await client.cacheSize() == 30)
  }

  @Test func purgeRefusesAPathNotEndingInTheBundleIdentifier() async throws {
    // A cache dir whose last component isn't the bundle identifier (which
    // this unbundled test binary has none of) must never be purged.
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("not-the-identifier")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let client = YtDlpClient(
      binaryURL: URL(fileURLWithPath: "/usr/bin/true"), cacheDir: dir,
      libraryURL: dir.appendingPathComponent("support/Library.sqlite"))
    await #expect(throws: (any Error).self) { try await client.purgeCache() }
  }

  @Test func purgeRemovesAudioButKeepsTheLibrary() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ytdlp-library-test-\(UUID().uuidString)")
    let cacheDir = root.appendingPathComponent("com.truehhart.slowed-and-reverb")
    let libraryURL = root.appendingPathComponent("Library.sqlite")
    try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let id = "durable-song"
    let webpageURL = "https://example.test/song"
    try Data("audio".utf8).write(to: cacheDir.appendingPathComponent("\(id).m4a"))
    try JSONSerialization.data(
      withJSONObject: ["title": "Durable Song", "webpageURL": webpageURL]
    ).write(to: cacheDir.appendingPathComponent("\(id).json"))

    let client = YtDlpClient(
      binaryURL: URL(fileURLWithPath: "/usr/bin/true"), cacheDir: cacheDir,
      libraryURL: libraryURL)
    #expect(await client.librarySnapshot().songs.map(\.track.title) == ["Durable Song"])

    try await client.purgeCache()

    #expect(await client.cachedAudio(id: id) == nil)
    let reopened = YtDlpClient(
      binaryURL: URL(fileURLWithPath: "/usr/bin/true"), cacheDir: cacheDir,
      libraryURL: libraryURL)
    let library = await reopened.librarySnapshot().songs
    #expect(library.map(\.track.title) == ["Durable Song"])
    #expect(library.first?.track.webpageURL.absoluteString == webpageURL)
  }
}

@Suite struct PlaylistLibraryPersistenceTests {
  @Test func persistsOrderedSharedSongsAcrossRestartsAndReimports() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ytdlp-playlist-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let libraryURL = root.appendingPathComponent("Library.sqlite")
    let client = makeLibraryClient(root: root, libraryURL: libraryURL)
    let a = persistedTrack("a", title: "First")
    let b = persistedTrack("b", title: "Second")
    let c = persistedTrack("c", title: "Third")

    await client.persistResolvedPlaylist(
      id: "one", title: "One", sourceURL: URL(string: "https://x/one")!, tracks: [b, a, b])
    await client.persistResolvedPlaylist(
      id: "two", title: "Two", sourceURL: URL(string: "https://x/two")!, tracks: [a, c])
    let original = await client.librarySnapshot()
    let songDates = Dictionary(uniqueKeysWithValues: original.songs.map { ($0.id, $0.addedAt) })
    let playlistDate = original.playlists.first { $0.id == "one" }?.addedAt
    #expect(original.playlists.first { $0.id == "one" }?.tracks.map(\.id) == ["b", "a", "b"])

    await client.persistResolvedPlaylist(
      id: "one", title: "One Updated", sourceURL: URL(string: "https://x/one-new")!,
      tracks: [c, b])
    let reopened = makeLibraryClient(root: root, libraryURL: libraryURL)
    let snapshot = await reopened.librarySnapshot()

    #expect(Set(snapshot.songs.map(\.id)) == Set(["a", "b", "c"]))
    #expect(snapshot.songs.allSatisfy { songDates[$0.id] == $0.addedAt })
    #expect(snapshot.playlists.first { $0.id == "one" }?.title == "One Updated")
    #expect(snapshot.playlists.first { $0.id == "one" }?.tracks.map(\.id) == ["c", "b"])
    #expect(snapshot.playlists.first { $0.id == "one" }?.addedAt == playlistDate)
    #expect(snapshot.playlists.first { $0.id == "two" }?.tracks.map(\.id) == ["a", "c"])
  }

  @Test func songRemovalDeletesOnlyTargetCacheAndCleansMemberships() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ytdlp-removal-test-\(UUID().uuidString)")
    let cache = root.appendingPathComponent("cache")
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let client = YtDlpClient(
      binaryURL: URL(fileURLWithPath: "/usr/bin/true"), cacheDir: cache,
      libraryURL: root.appendingPathComponent("Library.sqlite"))
    let a = persistedTrack("a", title: "First")
    let b = persistedTrack("b", title: "Second")
    await client.persistResolvedPlaylist(
      id: "one", title: "One", sourceURL: URL(string: "https://x/one")!, tracks: [a, b])
    for name in ["a.m4a", "a_thumb.jpg", "b.m4a"] {
      try Data(name.utf8).write(to: cache.appendingPathComponent(name))
    }

    try await client.removeLibrarySong(id: "a")
    let snapshot = await client.librarySnapshot()

    #expect(snapshot.songs.map(\.id) == ["b"])
    #expect(snapshot.playlists.first?.tracks.map(\.id) == ["b"])
    #expect(!FileManager.default.fileExists(atPath: cache.appendingPathComponent("a.m4a").path))
    #expect(
      !FileManager.default.fileExists(atPath: cache.appendingPathComponent("a_thumb.jpg").path))
    #expect(FileManager.default.fileExists(atPath: cache.appendingPathComponent("b.m4a").path))
  }

  @Test func playlistRemovalKeepsSongsAndCachedFiles() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ytdlp-removal-test-\(UUID().uuidString)")
    let cache = root.appendingPathComponent("cache")
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let client = YtDlpClient(
      binaryURL: URL(fileURLWithPath: "/usr/bin/true"), cacheDir: cache,
      libraryURL: root.appendingPathComponent("Library.sqlite"))
    let song = persistedTrack("a", title: "First")
    await client.persistResolvedPlaylist(
      id: "one", title: "One", sourceURL: URL(string: "https://x/one")!, tracks: [song])
    let audio = cache.appendingPathComponent("a.m4a")
    try Data("audio".utf8).write(to: audio)

    try await client.removeLibraryPlaylist(id: "one")
    let snapshot = await client.librarySnapshot()

    #expect(snapshot.playlists.isEmpty)
    #expect(snapshot.songs.map(\.id) == ["a"])
    #expect(FileManager.default.fileExists(atPath: audio.path))
  }

  @Test func cacheDeletionFailureKeepsSongMetadata() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ytdlp-removal-test-\(UUID().uuidString)")
    let cache = root.appendingPathComponent("cache")
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let client = YtDlpClient(
      binaryURL: URL(fileURLWithPath: "/usr/bin/true"), cacheDir: cache,
      libraryURL: root.appendingPathComponent("Library.sqlite"))
    let song = persistedTrack("a", title: "Protected")
    await client.persistResolvedPlaylist(
      id: "one", title: "One", sourceURL: URL(string: "https://x/one")!, tracks: [song])
    let audio = cache.appendingPathComponent("a.m4a")
    try Data("audio".utf8).write(to: audio)
    try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: audio.path)
    defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: audio.path) }

    await #expect(throws: (any Error).self) { try await client.removeLibrarySong(id: "a") }

    #expect(await client.librarySnapshot().songs.map(\.id) == ["a"])
  }

  @Test func migratesTheSongOnlyCoreDataStore() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ytdlp-migration-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let libraryURL = root.appendingPathComponent("Library.sqlite")
    try makeSongOnlyStore(at: libraryURL)

    let client = makeLibraryClient(root: root, libraryURL: libraryURL)
    let snapshot = await client.librarySnapshot()

    #expect(snapshot.songs.map(\.track.title) == ["Migrated"])
    #expect(snapshot.playlists.isEmpty)
  }

  private func makeLibraryClient(root: URL, libraryURL: URL) -> YtDlpClient {
    YtDlpClient(
      binaryURL: URL(fileURLWithPath: "/usr/bin/true"),
      cacheDir: root.appendingPathComponent("cache"), libraryURL: libraryURL)
  }

  private nonisolated func persistedTrack(_ id: String, title: String) -> Track {
    Track(
      id: id, title: title, webpageURL: URL(string: "https://example.test/\(id)")!,
      thumbnailURL: nil)
  }

  private func makeSongOnlyStore(at url: URL) throws {
    let model = NSManagedObjectModel()
    model.entities = [SongMetadata.makeEntity()]
    let container = NSPersistentContainer(name: "Library", managedObjectModel: model)
    let store = try container.persistentStoreCoordinator.addPersistentStore(
      ofType: NSSQLiteStoreType, configurationName: nil, at: url)
    let context = container.newBackgroundContext()
    try context.performAndWait {
      let metadata =
        NSEntityDescription.insertNewObject(
          forEntityName: "SongMetadata", into: context) as! SongMetadata
      metadata.update(from: persistedTrack("migrated", title: "Migrated"), sourceURL: nil)
      try context.save()
    }
    try container.persistentStoreCoordinator.remove(store)
  }
}
