import CoreData
import Foundation
import Synchronization

/// Thin wrapper over the bundled `yt-dlp` CLI. All process/network/filesystem
/// I/O lives here and, because this is an actor, runs off the main actor.
actor YtDlpClient: YtDlpClientProtocol {
  // Modest AAC-first default: WKWebView/AVFoundation reliably decode AAC/m4a;
  // a bare `bestaudio` often returns Opus-in-WebM.
  private nonisolated static let audioFormat =
    "bestaudio[ext=m4a]/bestaudio[acodec^=mp4a]/bestaudio[ext=mp3]/bestaudio"
  private nonisolated static let playlistMetadataConcurrency = 4

  private enum Binary {
    case bundled(URL)
    case fromPATH
  }

  private let binary: Binary
  private let libraryURL: URL
  private var libraryContainer: NSPersistentContainer?
  private var didInitializeLibrary = false
  /// Immutable and `Sendable`, so this stays nonisolated: callers read it
  /// without hopping onto the actor.
  let cacheDir: URL
  /// Monotonic download generation, matching Rust's `Arc<AtomicU64>`. A `let`
  /// of a `Sendable` type is nonisolated, so the Process pipe readers bump and
  /// read it without hopping onto the actor.
  private let generation = Atomic<UInt64>(0)
  private var activeProcesses: [UUID: Process] = [:]
  /// One in-flight fetch task per id, shared by concurrent callers. Plain
  /// actor state: check-and-insert runs before any `await`, so the dedup holds
  /// without an explicit lock.
  private var thumbnailFetches: [String: Task<URL?, Never>] = [:]

  init(binaryURL: URL? = nil, cacheDir: URL? = nil, libraryURL: URL? = nil) {
    self.binary = binaryURL.map(Binary.bundled) ?? Self.discoverBinary()
    self.cacheDir = cacheDir ?? Self.defaultCacheDir()
    self.libraryURL = libraryURL ?? Self.defaultLibraryURL()
    warmUp()
  }

  private nonisolated static func discoverBinary() -> Binary {
    if let resourceURL = Bundle.main.resourceURL {
      let candidate = resourceURL.appendingPathComponent("yt-dlp")
      if FileManager.default.isExecutableFile(atPath: candidate.path) {
        return .bundled(candidate)
      }
    }
    return .fromPATH  // dev fallback; mise provides yt-dlp on PATH
  }

  private nonisolated static func defaultCacheDir() -> URL {
    let base =
      FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    let identifier = Bundle.main.bundleIdentifier ?? "com.truehhart.slowed-and-reverb"
    return base.appendingPathComponent(identifier)
  }

  private nonisolated static func defaultLibraryURL() -> URL {
    let base =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    let identifier = Bundle.main.bundleIdentifier ?? "com.truehhart.slowed-and-reverb"
    return base.appendingPathComponent(identifier).appendingPathComponent("Library.store")
  }

  private nonisolated static func makeLibraryContainer(at url: URL) throws
    -> NSPersistentContainer
  {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let model = NSManagedObjectModel()
    model.entities = [
      SongMetadata.makeEntity(), PlaylistMetadata.makeEntity(),
      PlaylistSongMembership.makeEntity(),
    ]
    let container = NSPersistentContainer(name: "Library", managedObjectModel: model)
    try container.persistentStoreCoordinator.addPersistentStore(
      ofType: NSSQLiteStoreType, configurationName: nil, at: url,
      options: [
        NSMigratePersistentStoresAutomaticallyOption: true,
        NSInferMappingModelAutomaticallyOption: true,
      ])
    return container
  }

  private func initializedLibraryContainer() -> NSPersistentContainer? {
    if didInitializeLibrary { return libraryContainer }
    didInitializeLibrary = true
    do {
      let container = try Self.makeLibraryContainer(at: libraryURL)
      libraryContainer = container
      Self.migrateLegacyMetadata(in: cacheDir, to: container)
      return container
    } catch {
      Log.ytdlp.error("library database unavailable: \(error, privacy: .public)")
      return nil
    }
  }

  private nonisolated func makeProcess(args: [String]) -> Process {
    let process = Process()
    switch binary {
    case .bundled(let url):
      process.executableURL = url
      process.arguments = args
    case .fromPATH:
      process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
      process.arguments = ["yt-dlp"] + args
    }
    return process
  }

  /// Fire-and-forget: primes yt-dlp's cold start so the first real fetch is faster.
  private nonisolated func warmUp() {
    let process = makeProcess(args: ["--version"])
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    Task.detached {
      try? process.run()
      process.waitUntilExit()
    }
  }

  // MARK: - resolve

  func resolve(url: String) async throws -> ResolvedTracks {
    Log.ytdlp.debug("resolve: \(url, privacy: .public)")
    let result = try await run(args: ["-J", "--flat-playlist", "--no-warnings", url])
    guard result.status == 0 else {
      throw YtDlpError.failed(
        String(decoding: result.stderr, as: UTF8.self).trimmingCharacters(
          in: .whitespacesAndNewlines))
    }
    guard let root = try? JSONDecoder().decode(RawEntry.self, from: result.stdout) else {
      throw YtDlpError.invalidResponse
    }
    // A playlist carries `entries`; a single video is its own lone entry.
    let entries = root.entries.map { $0.compactMap(\.value) } ?? [root]
    let tracks = entries.compactMap(Self.parseTrack)
    guard !tracks.isEmpty else { throw YtDlpError.noPlayableTracks }
    let sourceURL = URL(string: url)
    if root.entries != nil, let playlistID = root.id, !playlistID.isEmpty,
      let playlistTitle = root.title, !playlistTitle.isEmpty, let sourceURL
    {
      persistResolvedPlaylist(
        id: playlistID, title: playlistTitle, sourceURL: sourceURL, tracks: tracks)
    } else {
      persistMetadata(for: tracks, sourceURL: sourceURL)
    }
    guard root.entries != nil else { return ResolvedTracks(tracks: tracks) }
    return ResolvedTracks(tracks: tracks, metadataUpdates: metadataUpdates(for: tracks))
  }

  private func metadataUpdates(for tracks: [Track]) -> AsyncStream<Track> {
    let (stream, continuation) = AsyncStream<Track>.makeStream()
    Task { [self] in
      await enrichPlaylistTracks(tracks, continuation: continuation)
      continuation.finish()
    }
    return stream
  }

  private func enrichPlaylistTracks(
    _ tracks: [Track], continuation: AsyncStream<Track>.Continuation
  ) async {
    guard !tracks.isEmpty else { return }
    let limit = min(Self.playlistMetadataConcurrency, tracks.count)

    await withTaskGroup(of: Track?.self) { group in
      var nextIndex = 0
      for _ in 0..<limit {
        let track = tracks[nextIndex]
        nextIndex += 1
        group.addTask { [self] in
          await enrichPlaylistTrack(track)
        }
      }

      for await track in group {
        if let track {
          persistMetadata(for: [track], sourceURL: nil)
          continuation.yield(track)
        }
        guard nextIndex < tracks.count else { continue }
        let pendingTrack = tracks[nextIndex]
        nextIndex += 1
        group.addTask { [self] in
          await enrichPlaylistTrack(pendingTrack)
        }
      }
    }
  }

  private func enrichPlaylistTrack(_ fallback: Track) async -> Track? {
    do {
      let result = try await run(args: [
        "-J", "--no-playlist", "--no-warnings", fallback.webpageURL.absoluteString,
      ])
      guard result.status == 0 else {
        let error = String(decoding: result.stderr, as: UTF8.self).trimmingCharacters(
          in: .whitespacesAndNewlines)
        Log.ytdlp.error(
          "metadata enrichment failed for \(fallback.id, privacy: .public): \(error, privacy: .public)"
        )
        return nil
      }
      guard let entry = try? JSONDecoder().decode(RawEntry.self, from: result.stdout),
        let track = Self.parseTrack(entry), track.id == fallback.id
      else {
        Log.ytdlp.error("invalid metadata response for \(fallback.id, privacy: .public)")
        return nil
      }
      return Self.merging(track, fallback: fallback)
    } catch {
      Log.ytdlp.error(
        "metadata enrichment failed for \(fallback.id, privacy: .public): \(error, privacy: .public)"
      )
      return nil
    }
  }

  /// The subset of yt-dlp's `-J` schema we consume. `entries` is present for
  /// playlists; a single-video response decodes as one `RawEntry`.
  nonisolated struct RawEntry: Decodable {
    nonisolated struct Thumbnail: Decodable {
      var url: String?
    }
    var id: String?
    var title: String?
    var artist: String?
    var creator: String?
    var channel: String?
    var uploader: String?
    var webpageURL: String?
    var thumbnail: String?
    var thumbnails: [Thumbnail]?
    var duration: Double?
    var entries: [LossyEntry]?

    /// Decodes to nil instead of failing the whole playlist when one entry
    /// is malformed, mirroring the old lenient JSONSerialization loop (some
    /// yt-dlp extractors emit odd entry shapes).
    nonisolated struct LossyEntry: Decodable {
      let value: RawEntry?
      init(from decoder: any Decoder) {
        value = try? RawEntry(from: decoder)
      }
    }

    enum CodingKeys: String, CodingKey {
      case id, title, artist, creator, channel, uploader, thumbnail, thumbnails, duration, entries
      case webpageURL = "webpage_url"
    }
  }

  /// Flat-playlist entries for unavailable videos carry a bracketed
  /// placeholder title (`[Private video]`, `[Deleted video]`, ...) or none at
  /// all. Drop them here instead of queuing a track that can never play.
  nonisolated static func isUnavailableTitle(_ title: String) -> Bool {
    let t = title.trimmingCharacters(in: .whitespaces)
    guard t.hasPrefix("["), t.hasSuffix("]") else { return false }
    let lower = t.lowercased()
    return ["private", "deleted", "unavailable"].contains { lower.contains($0) }
  }

  nonisolated static func parseTrack(_ entry: RawEntry) -> Track? {
    guard let id = entry.id, !id.isEmpty else { return nil }
    guard let title = entry.title, !title.isEmpty, !isUnavailableTitle(title) else { return nil }
    guard let webpageURL = URL(string: entry.webpageURL ?? "https://www.youtube.com/watch?v=\(id)")
    else { return nil }

    let thumbnailURL: URL?
    if let thumb = entry.thumbnail {
      thumbnailURL = URL(string: thumb)
    } else if let last = entry.thumbnails?.last?.url {
      thumbnailURL = URL(string: last)
    } else {
      thumbnailURL = nil
    }

    let artist = inferredArtist(for: entry)
    return Track(
      id: id, title: titleWithoutArtist(title, artist: artist), artist: artist,
      webpageURL: webpageURL,
      thumbnailURL: thumbnailURL,
      duration: entry.duration)
  }

  nonisolated static func inferredArtist(for entry: RawEntry) -> String? {
    for candidate in [entry.artist, entry.creator] {
      if let value = cleanedArtist(candidate) { return value }
    }

    if let title = entry.title {
      for separator in [" - ", " – "] {
        if let range = title.range(of: separator),
          let value = cleanedArtist(String(title[..<range.lowerBound]))
        {
          return value
        }
      }
    }

    for candidate in [entry.channel, entry.uploader] {
      if let value = cleanedArtist(candidate) { return value }
    }
    return nil
  }

  nonisolated static func titleWithoutArtist(_ title: String, artist: String?) -> String {
    guard let artist else { return title }
    for separator in [" - ", " – "] {
      guard let range = title.range(of: separator) else { continue }
      let prefix = title[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
      let remainder = title[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
      if prefix.caseInsensitiveCompare(artist) == .orderedSame, !remainder.isEmpty {
        return remainder
      }
    }
    return title
  }

  private nonisolated static func merging(_ enriched: Track, fallback: Track) -> Track {
    Track(
      id: fallback.id, title: enriched.title, artist: enriched.artist ?? fallback.artist,
      webpageURL: enriched.webpageURL,
      thumbnailURL: enriched.thumbnailURL ?? fallback.thumbnailURL,
      duration: enriched.duration ?? fallback.duration)
  }

  private nonisolated static func cleanedArtist(_ candidate: String?) -> String? {
    guard var value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty
    else { return nil }
    if value.hasSuffix(" - Topic") {
      value.removeLast(" - Topic".count)
    }
    let generic = ["official video", "official audio", "music video", "lyrics", "lyric video"]
    guard value.count <= 100, !generic.contains(value.lowercased()) else { return nil }
    return value
  }

  // MARK: - library

  private nonisolated struct TrackMeta: Codable {
    let title: String
    let artist: String?
    let webpageURL: URL?
    let thumbnailURL: URL?
    let duration: TimeInterval?
    let sourceURL: URL?
  }

  private nonisolated struct StoredMetadata {
    let id: String
    let title: String
    let artist: String?
    let webpageURL: String
    let thumbnailURL: String?
    let duration: TimeInterval?
    let sourceURL: String?
    let addedAt: Date

    var track: Track? {
      guard let webpageURL = URL(string: webpageURL) else { return nil }
      return Track(
        id: id, title: title, artist: artist, webpageURL: webpageURL,
        thumbnailURL: thumbnailURL.flatMap(URL.init(string:)), duration: duration)
    }
  }

  private func persistMetadata(for tracks: [Track], sourceURL: URL?) {
    guard let libraryContainer = initializedLibraryContainer() else { return }
    let context = libraryContainer.newBackgroundContext()
    do {
      try context.performAndWait {
        let request = NSFetchRequest<SongMetadata>(entityName: "SongMetadata")
        request.predicate = NSPredicate(format: "id IN %@", tracks.map(\.id))
        var existing = Dictionary(
          uniqueKeysWithValues: try context.fetch(request).map { ($0.id, $0) })
        for track in tracks {
          let metadata: SongMetadata
          if let stored = existing[track.id] {
            metadata = stored
          } else {
            metadata =
              NSEntityDescription.insertNewObject(
                forEntityName: "SongMetadata", into: context) as! SongMetadata
            existing[track.id] = metadata
          }
          metadata.update(from: track, sourceURL: sourceURL)
        }
        try context.save()
      }
    } catch {
      Log.ytdlp.error("could not store metadata: \(error, privacy: .public)")
    }
  }

  private func persistPlaylist(id: String, title: String, sourceURL: URL, tracks: [Track]) {
    guard let libraryContainer = initializedLibraryContainer() else { return }
    let context = libraryContainer.newBackgroundContext()
    do {
      try context.performAndWait {
        let playlistRequest = NSFetchRequest<PlaylistMetadata>(entityName: "PlaylistMetadata")
        playlistRequest.predicate = NSPredicate(format: "id == %@", id)
        playlistRequest.fetchLimit = 1
        let playlist =
          try context.fetch(playlistRequest).first
          ?? NSEntityDescription.insertNewObject(
            forEntityName: "PlaylistMetadata", into: context) as! PlaylistMetadata
        let isNew = playlist.isInserted
        playlist.id = id
        playlist.title = title
        playlist.sourceURL = sourceURL.absoluteString
        if isNew { playlist.addedAt = Date() }

        let oldMemberships = NSFetchRequest<PlaylistSongMembership>(
          entityName: "PlaylistSongMembership")
        oldMemberships.predicate = NSPredicate(format: "playlistID == %@", id)
        try context.fetch(oldMemberships).forEach(context.delete)
        for (position, track) in tracks.enumerated() {
          let membership =
            NSEntityDescription.insertNewObject(
              forEntityName: "PlaylistSongMembership", into: context)
            as! PlaylistSongMembership
          membership.playlistID = id
          membership.songID = track.id
          membership.position = Int64(position)
        }
        try context.save()
      }
    } catch {
      Log.ytdlp.error("could not store playlist: \(error, privacy: .public)")
    }
  }

  func persistResolvedPlaylist(id: String, title: String, sourceURL: URL, tracks: [Track]) {
    persistMetadata(for: tracks, sourceURL: nil)
    persistPlaylist(id: id, title: title, sourceURL: sourceURL, tracks: tracks)
  }

  private func readMetadata(id: String) -> StoredMetadata? {
    guard let libraryContainer = initializedLibraryContainer() else { return nil }
    let context = libraryContainer.newBackgroundContext()
    return try? context.performAndWait {
      let request = NSFetchRequest<SongMetadata>(entityName: "SongMetadata")
      request.predicate = NSPredicate(format: "id == %@", id)
      request.fetchLimit = 1
      return try context.fetch(request).first.map(Self.storedMetadata)
    }
  }

  private func allMetadata() -> [StoredMetadata] {
    guard let libraryContainer = initializedLibraryContainer() else { return [] }
    let context = libraryContainer.newBackgroundContext()
    return
      (try? context.performAndWait {
        let request = NSFetchRequest<SongMetadata>(entityName: "SongMetadata")
        request.sortDescriptors = [NSSortDescriptor(key: "addedAt", ascending: false)]
        return try context.fetch(request).map(Self.storedMetadata)
      }) ?? []
  }

  private nonisolated static func storedMetadata(_ metadata: SongMetadata) -> StoredMetadata {
    StoredMetadata(
      id: metadata.id, title: metadata.title, artist: metadata.artist,
      webpageURL: metadata.webpageURL, thumbnailURL: metadata.thumbnailURL,
      duration: metadata.duration?.doubleValue, sourceURL: metadata.sourceURL,
      addedAt: metadata.addedAt)
  }

  func librarySnapshot() -> LibrarySnapshot {
    guard let libraryContainer = initializedLibraryContainer() else { return .empty }
    let context = libraryContainer.newBackgroundContext()
    return
      (try? context.performAndWait {
        let songRequest = NSFetchRequest<SongMetadata>(entityName: "SongMetadata")
        songRequest.sortDescriptors = [NSSortDescriptor(key: "addedAt", ascending: false)]
        let metadata = try context.fetch(songRequest).map(Self.storedMetadata)
        let songs = metadata.compactMap { stored in
          stored.track.map { LibrarySong(track: $0, addedAt: stored.addedAt) }
        }
        let tracksByID = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, $0.track) })

        let playlistRequest = NSFetchRequest<PlaylistMetadata>(entityName: "PlaylistMetadata")
        playlistRequest.sortDescriptors = [NSSortDescriptor(key: "addedAt", ascending: false)]
        let storedPlaylists = try context.fetch(playlistRequest)
        let membershipRequest = NSFetchRequest<PlaylistSongMembership>(
          entityName: "PlaylistSongMembership")
        membershipRequest.sortDescriptors = [NSSortDescriptor(key: "position", ascending: true)]
        let memberships = Dictionary(
          grouping: try context.fetch(membershipRequest), by: \.playlistID)
        let playlists = storedPlaylists.compactMap { playlist -> LibraryPlaylist? in
          guard let sourceURL = URL(string: playlist.sourceURL) else { return nil }
          let tracks = (memberships[playlist.id] ?? []).compactMap { tracksByID[$0.songID] }
          return LibraryPlaylist(
            id: playlist.id, title: playlist.title, sourceURL: sourceURL,
            addedAt: playlist.addedAt, tracks: tracks)
        }
        return LibrarySnapshot(songs: songs, playlists: playlists)
      }) ?? .empty
  }

  func removeLibrarySong(id: String) throws {
    cancelActiveDownload()
    for url in cachedFiles(forSongID: id) {
      do {
        try FileManager.default.removeItem(at: url)
      } catch {
        throw YtDlpError.failed("could not delete cached file \(url.lastPathComponent): \(error)")
      }
    }
    guard let libraryContainer = initializedLibraryContainer() else {
      throw YtDlpError.failed("library database unavailable")
    }
    let context = libraryContainer.newBackgroundContext()
    try context.performAndWait {
      let memberships = NSFetchRequest<PlaylistSongMembership>(
        entityName: "PlaylistSongMembership")
      memberships.predicate = NSPredicate(format: "songID == %@", id)
      try context.fetch(memberships).forEach(context.delete)
      let songs = NSFetchRequest<SongMetadata>(entityName: "SongMetadata")
      songs.predicate = NSPredicate(format: "id == %@", id)
      try context.fetch(songs).forEach(context.delete)
      try context.save()
    }
  }

  func removeLibraryPlaylist(id: String) throws {
    guard let libraryContainer = initializedLibraryContainer() else {
      throw YtDlpError.failed("library database unavailable")
    }
    let context = libraryContainer.newBackgroundContext()
    try context.performAndWait {
      let memberships = NSFetchRequest<PlaylistSongMembership>(
        entityName: "PlaylistSongMembership")
      memberships.predicate = NSPredicate(format: "playlistID == %@", id)
      try context.fetch(memberships).forEach(context.delete)
      let playlists = NSFetchRequest<PlaylistMetadata>(entityName: "PlaylistMetadata")
      playlists.predicate = NSPredicate(format: "id == %@", id)
      try context.fetch(playlists).forEach(context.delete)
      try context.save()
    }
  }

  private func cachedFiles(forSongID id: String) -> [URL] {
    regularFiles(in: cacheDir).filter {
      let stem = $0.deletingPathExtension().lastPathComponent
      return stem == id || stem == "\(id)_thumb"
    }
  }

  private nonisolated static func migrateLegacyMetadata(
    in cacheDir: URL, to container: NSPersistentContainer
  ) {
    let legacyEntries = regularFiles(in: cacheDir).compactMap { path -> (URL, String, TrackMeta)? in
      guard path.pathExtension == "json", let data = try? Data(contentsOf: path),
        let metadata = try? JSONDecoder().decode(TrackMeta.self, from: data)
      else { return nil }
      let id = path.deletingPathExtension().lastPathComponent
      return (path, id, metadata)
    }
    guard !legacyEntries.isEmpty else { return }

    let context = container.newBackgroundContext()
    do {
      try context.performAndWait {
        let request = NSFetchRequest<SongMetadata>(entityName: "SongMetadata")
        request.predicate = NSPredicate(format: "id IN %@", legacyEntries.map { $0.1 })
        let existing = Dictionary(
          uniqueKeysWithValues: try context.fetch(request).map { ($0.id, $0) })
        for (_, id, legacy) in legacyEntries {
          let webpageURL =
            legacy.webpageURL ?? URL(string: "https://www.youtube.com/watch?v=\(id)")!
          let track = Track(
            id: id, title: legacy.title, artist: legacy.artist, webpageURL: webpageURL,
            thumbnailURL: legacy.thumbnailURL, duration: legacy.duration)
          let metadata =
            existing[id]
            ?? NSEntityDescription.insertNewObject(
              forEntityName: "SongMetadata", into: context) as! SongMetadata
          metadata.update(from: track, sourceURL: legacy.sourceURL)
        }
        try context.save()
      }
      for (path, _, _) in legacyEntries {
        try FileManager.default.removeItem(at: path)
      }
    } catch {
      Log.ytdlp.error("could not migrate legacy metadata: \(error, privacy: .public)")
    }
  }

  // MARK: - cache scan

  func cachedAudio(id: String) -> CachedAudioInfo? {
    guard let path = cachedAudioPath(id: id) else { return nil }
    return cachedAudioInfo(id: id, path: path, metadata: readMetadata(id: id))
  }

  func cachedAudio(url: String) -> CachedAudioInfo? {
    guard let requestedURL = URL(string: url) else { return nil }
    for metadata in allMetadata() {
      guard
        metadata.webpageURL == requestedURL.absoluteString
          || metadata.sourceURL == requestedURL.absoluteString,
        let path = cachedAudioPath(id: metadata.id)
      else { continue }
      return cachedAudioInfo(id: metadata.id, path: path, metadata: metadata)
    }
    return nil
  }

  private func cachedAudioInfo(id: String, path: URL, metadata: StoredMetadata?) -> CachedAudioInfo
  {
    CachedAudioInfo(
      path: path, id: id, title: metadata?.title, artist: metadata?.artist,
      webpageURL: metadata.flatMap { URL(string: $0.webpageURL) },
      thumbnailURL: metadata?.thumbnailURL.flatMap { URL(string: $0) },
      duration: metadata?.duration)
  }

  private func cachedAudioPath(id: String) -> URL? {
    regularFiles(in: cacheDir).first { url in
      url.pathExtension != "json" && url.deletingPathExtension().lastPathComponent == id
    }
  }

  func cacheSize() -> UInt64 {
    regularFiles(in: cacheDir, keys: [.fileSizeKey]).reduce(UInt64(0)) { total, url in
      guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
        return total
      }
      return total + UInt64(size)
    }
  }

  func purgeCache() throws {
    // Destructive-op guard: refuse unless the resolved dir is our own
    // identifier-scoped cache, never a broad path.
    let identifier = Bundle.main.bundleIdentifier ?? "com.truehhart.slowed-and-reverb"
    guard cacheDir.lastPathComponent == identifier else {
      throw YtDlpError.failed("refusing to purge unexpected path: \(cacheDir.path)")
    }
    for url in regularFiles(in: cacheDir) {
      try? FileManager.default.removeItem(at: url)
    }
  }

  /// Top-level regular files in `dir` (never recurses into subdirectories).
  private nonisolated static func regularFiles(
    in dir: URL, keys: [URLResourceKey] = []
  ) -> [URL] {
    let entries =
      (try? FileManager.default.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: keys + [.isRegularFileKey])) ?? []
    return entries.filter {
      (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }
  }

  private nonisolated func regularFiles(
    in dir: URL, keys: [URLResourceKey] = []
  ) -> [URL] {
    Self.regularFiles(in: dir, keys: keys)
  }

  // MARK: - download

  func cancelActiveDownload() {
    _ = generation.wrappingAdd(1, ordering: .sequentiallyConsistent)
    for process in activeProcesses.values where process.isRunning {
      process.terminate()
    }
  }

  func download(url: String, id: String, progress: @escaping @Sendable (Double) -> Void)
    async throws -> URL
  {
    // Bump first: this call is now the current selection, even a cache hit
    // below supersedes any older in-flight download.
    let myGeneration = generation.wrappingAdd(1, ordering: .sequentiallyConsistent).newValue

    try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    if let cached = cachedAudioPath(id: id) {
      return cached
    }

    let outputTemplate = cacheDir.appendingPathComponent("%(id)s.%(ext)s").path
    let process = makeProcess(args: [
      "-f", Self.audioFormat,
      "--no-playlist", "--no-warnings",
      "--newline", "--progress",
      "-o", outputTemplate,
      "--print", "after_move:filepath",
      "--no-simulate",
      url,
    ])
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    Log.ytdlp.debug("download start: \(url, privacy: .public)")
    do {
      try process.run()
    } catch {
      throw YtDlpError.launchFailed(error.localizedDescription)
    }
    let processID = UUID()
    activeProcesses[processID] = process
    defer { activeProcesses.removeValue(forKey: processID) }

    let errorLines = Mutex<[String]>([])
    let lastPath = Mutex<String>("")

    async let stdoutDrain: Void = Task.detached { [self] in
      for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
        if generation.load(ordering: .sequentiallyConsistent) != myGeneration {
          process.terminate()
          break
        }
        if let percent = Self.parsePercent(line) {
          progress(percent)
          continue
        }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, !trimmed.hasPrefix("[") {
          lastPath.withLock { $0 = trimmed }
        }
      }
    }.value
    async let stderrDrain: Void = Task.detached { [self] in
      for try await line in stderrPipe.fileHandleForReading.bytes.lines {
        if generation.load(ordering: .sequentiallyConsistent) != myGeneration {
          process.terminate()
          break
        }
        if let percent = Self.parsePercent(line) {
          progress(percent)
        } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
          errorLines.withLock { $0.append(line) }
        }
      }
    }.value
    _ = try? await (stdoutDrain, stderrDrain)
    await Task.detached { process.waitUntilExit() }.value

    guard generation.load(ordering: .sequentiallyConsistent) == myGeneration else {
      throw YtDlpError.superseded
    }
    guard process.terminationStatus == 0 else {
      throw YtDlpError.failed(errorLines.withLock { $0.joined(separator: "\n") })
    }
    let path = lastPath.withLock { $0 }
    guard !path.isEmpty else { throw YtDlpError.noOutputPath }
    Log.ytdlp.debug("download ready: \(path, privacy: .public)")
    return URL(fileURLWithPath: path)
  }

  /// Pull the percentage out of a yt-dlp `[download]  12.3% of …` progress line.
  nonisolated static func parsePercent(_ line: String) -> Double? {
    guard let range = line.range(of: "[download]") else { return nil }
    var rest = line[range.upperBound...]
    while let first = rest.first, first == " " { rest = rest.dropFirst() }
    guard let percentIndex = rest.firstIndex(of: "%") else { return nil }
    return Double(rest[rest.startIndex..<percentIndex].trimmingCharacters(in: .whitespaces))
  }

  /// Non-streaming run, used by `resolve` (no progress to parse).
  private func run(args: [String]) async throws -> (stdout: Data, stderr: Data, status: Int32) {
    let process = makeProcess(args: args)
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    do {
      try process.run()
    } catch {
      throw YtDlpError.launchFailed(error.localizedDescription)
    }
    async let stdoutData = Task.detached {
      (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
    }.value
    async let stderrData = Task.detached {
      (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
    }.value
    let (out, err) = await (stdoutData, stderrData)
    await Task.detached { process.waitUntilExit() }.value
    return (out, err, process.terminationStatus)
  }

  // MARK: - thumbnails

  private func existingThumbnailPath(id: String) -> URL? {
    let stem = "\(id)_thumb"
    return regularFiles(in: cacheDir).first { $0.deletingPathExtension().lastPathComponent == stem }
  }

  func artworkURL(for track: Track) async -> URL? {
    if let existing = existingThumbnailPath(id: track.id) { return existing }
    guard let remote = track.thumbnailURL else { return nil }
    // Reuse an in-flight fetch (check-and-insert below runs before any await,
    // so two callers for the same id share one task).
    if let inFlight = thumbnailFetches[track.id] { return await inFlight.value }

    let id = track.id
    let cacheDir = self.cacheDir
    let task = Task<URL?, Never>.detached {
      let ext =
        remote.absoluteString.split(separator: "?").first.map(String.init)?.lowercased()
          .hasSuffix(".webp") == true
        ? "webp" : "jpg"
      let destination = cacheDir.appendingPathComponent("\(id)_thumb.\(ext)")
      do {
        let (data, _) = try await URLSession.shared.data(from: remote)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try data.write(to: destination)
        return destination
      } catch {
        return nil
      }
    }
    thumbnailFetches[id] = task
    let result = await task.value
    thumbnailFetches[id] = nil
    return result
  }
}
