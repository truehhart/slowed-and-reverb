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

@Suite struct CacheScanAndMetaRoundTripTests {
  @Test func findsCachedAudioAndRoundTripsTitleMetadata() async throws {
    let unresolved = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ytdlp-cache-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: unresolved, withIntermediateDirectories: true)
    let dir = canonical(unresolved)
    defer { try? FileManager.default.removeItem(at: unresolved) }

    let client = YtDlpClient(binaryURL: URL(fileURLWithPath: "/usr/bin/true"), cacheDir: dir)

    let audioPath = dir.appendingPathComponent("ccccccccccc.m4a")
    try Data("audio".utf8).write(to: audioPath)
    // A decoy .json with a non-metadata payload must never be picked as the audio file.
    try Data("not the audio".utf8).write(to: dir.appendingPathComponent("ccccccccccc.json"))
    try JSONSerialization.data(withJSONObject: ["title": "Cached Title"])
      .write(to: dir.appendingPathComponent("ccccccccccc.json"))

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

    let client = YtDlpClient(binaryURL: URL(fileURLWithPath: "/usr/bin/true"), cacheDir: dir)
    let id = "soundcloud-track"
    let webpageURL = "https://soundcloud.com/artist/song"
    let audioPath = dir.appendingPathComponent("\(id).m4a")
    try Data("audio".utf8).write(to: audioPath)
    try JSONSerialization.data(
      withJSONObject: ["title": "Cached Song", "webpageURL": webpageURL]
    ).write(to: dir.appendingPathComponent("\(id).json"))

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

    let client = YtDlpClient(binaryURL: URL(fileURLWithPath: "/usr/bin/true"), cacheDir: dir)
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

    let client = YtDlpClient(binaryURL: URL(fileURLWithPath: "/usr/bin/true"), cacheDir: dir)
    await #expect(throws: (any Error).self) { try await client.purgeCache() }
  }
}
