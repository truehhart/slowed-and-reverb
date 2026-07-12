import Foundation
import Synchronization

/// Thin wrapper over the bundled `yt-dlp` CLI. All process/network/filesystem
/// I/O lives here and, because this is an actor, runs off the main actor.
actor YtDlpClient: YtDlpClientProtocol {
  // Modest AAC-first default: WKWebView/AVFoundation reliably decode AAC/m4a;
  // a bare `bestaudio` often returns Opus-in-WebM.
  private nonisolated static let audioFormat =
    "bestaudio[ext=m4a]/bestaudio[acodec^=mp4a]/bestaudio[ext=mp3]/bestaudio"

  private enum Binary {
    case bundled(URL)
    case fromPATH
  }

  private let binary: Binary
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

  init(binaryURL: URL? = nil, cacheDir: URL? = nil) {
    self.binary = binaryURL.map(Binary.bundled) ?? Self.discoverBinary()
    self.cacheDir = cacheDir ?? Self.defaultCacheDir()
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

  func resolve(url: String) async throws -> [Track] {
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
    writeCachedTitles(for: tracks)
    return tracks
  }

  /// The subset of yt-dlp's `-J` schema we consume. `entries` is present for
  /// playlists; a single-video response decodes as one `RawEntry`.
  nonisolated struct RawEntry: Decodable {
    nonisolated struct Thumbnail: Decodable {
      var url: String?
    }
    var id: String?
    var title: String?
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
      case id, title, thumbnail, thumbnails, duration, entries
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

    return Track(
      id: id, title: title, webpageURL: webpageURL, thumbnailURL: thumbnailURL,
      duration: entry.duration)
  }

  // MARK: - per-track title cache (meta json alongside the audio file)

  private nonisolated struct TitleMeta: Codable {
    let title: String
  }

  private func metaPath(id: String) -> URL {
    cacheDir.appendingPathComponent("\(id).json")
  }

  private func writeCachedTitles(for tracks: [Track]) {
    try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    for track in tracks {
      guard let data = try? JSONEncoder().encode(TitleMeta(title: track.title)) else { continue }
      try? data.write(to: metaPath(id: track.id))
    }
  }

  private func readCachedTitle(id: String) -> String? {
    guard let data = try? Data(contentsOf: metaPath(id: id)),
      let meta = try? JSONDecoder().decode(TitleMeta.self, from: data)
    else { return nil }
    return meta.title
  }

  // MARK: - cache scan

  func cachedAudio(id: String) -> CachedAudioInfo? {
    guard let path = cachedAudioPath(id: id) else { return nil }
    return CachedAudioInfo(path: path, title: readCachedTitle(id: id))
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
  private func regularFiles(in dir: URL, keys: [URLResourceKey] = []) -> [URL] {
    let entries =
      (try? FileManager.default.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: keys + [.isRegularFileKey])) ?? []
    return entries.filter {
      (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }
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
