import Foundation
import Observation

@MainActor
@Observable
final class PlayerModel {
  // MARK: queue / playback state (read-only for UI)

  private(set) var queue: [Track] = []
  /// Index of the current track, -1 when nothing selected.
  private(set) var index: Int = -1
  private(set) var status: PlayerStatus = .idle
  private(set) var repeatMode: RepeatMode = .off
  /// yt-dlp progress percent (0–100) for any in-flight download, nil when none.
  private(set) var downloadProgress: Double?
  /// True while any download runs (foreground play or background preload).
  private(set) var isDownloading = false
  /// Last user-facing error string (yt-dlp stderr etc.), nil when clear.
  private(set) var lastError: String?
  private(set) var libraryRevision = 0

  var currentTrack: Track? {
    queue.indices.contains(index) ? queue[index] : nil
  }

  // MARK: transport position (seconds, real timeline; divide by speed for perceived)

  private(set) var currentTime: TimeInterval = 0
  private(set) var duration: TimeInterval = 0

  // MARK: effect controls (UI writes; setters push into the audio engine live)

  /// Playback speed 0.5...1.0 (UI shows 50–100).
  var speed: Double = 0.85 {
    didSet {
      audioEngine.speed = speed
      refreshPosition()
      updateNowPlayingPosition()
    }
  }
  /// Reverb wet mix 0...1 (UI shows 0–100).
  var reverbMix: Double = 0.6 {
    didSet { audioEngine.reverbMix = reverbMix }
  }
  var reverbSpace: ReverbSpace = .hall {
    didSet { audioEngine.reverbSpace = reverbSpace }
  }
  /// Highpass into the reverb send, Hz (e.g. 80/160/240).
  var reverbCutoff: Double = 80 {
    didSet { audioEngine.reverbCutoff = reverbCutoff }
  }
  /// Master volume 0...1. Setting it while muted unmutes.
  var volume: Double = 1 {
    didSet {
      if isMuted { isMuted = false }
      audioEngine.volume = volume
    }
  }
  private(set) var isMuted = false {
    didSet { audioEngine.isMuted = isMuted }
  }

  // MARK: dependencies + internal state

  private let ytdlp: any YtDlpClientProtocol
  private let audioEngine: any AudioEngineProtocol
  private let nowPlaying = NowPlayingController()

  private struct DownloadHandle {
    let id: UUID
    let task: Task<URL, Error>
  }

  private var playToken = 0
  private var requestToken = 0
  private var consecutiveFailures = 0
  private var pathCache: [String: URL] = [:]
  private var downloadTasks: [String: DownloadHandle] = [:]
  private var activeDownloadIDs: Set<UUID> = []
  private var progressDownloadID: UUID?
  private var positionTask: Task<Void, Never>?

  private static let prevRestartSeconds: TimeInterval = 2
  private static let lookaheadCount = 2

  convenience init() {
    self.init(ytdlp: YtDlpClient(), audioEngine: AVFoundationAudioEngine())
  }

  /// Injectable seam for tests: fakes both the yt-dlp process and the audio
  /// engine so queue/token/repeat/failure-skip logic is testable without
  /// network access or real audio hardware.
  init(ytdlp: any YtDlpClientProtocol, audioEngine: any AudioEngineProtocol) {
    self.ytdlp = ytdlp
    self.audioEngine = audioEngine

    audioEngine.speed = speed
    audioEngine.reverbMix = reverbMix
    audioEngine.reverbSpace = reverbSpace
    audioEngine.reverbCutoff = reverbCutoff
    audioEngine.volume = volume
    audioEngine.isMuted = isMuted

    audioEngine.onEnded = { [weak self] in
      guard let self else { return }
      Log.player.debug("auto-advance")
      Task { await self.advance(fromEnded: true) }
    }

    nowPlaying.delegate = self
  }

  // MARK: actions

  /// Replace the queue with the resolved track(s) of `url` and play the first.
  /// A `t=`/`start=` timecode in the URL applies to the first track only.
  /// Checks the on-disk cache first for single-video URLs (fast path, then
  /// refreshes the title in the background if it was missing).
  func load(url: String) async {
    requestToken += 1
    let request = requestToken
    lastError = nil
    let startAt = URLParsing.startSeconds(from: url)

    if let (track, path, hasTitle) = await cachedTrack(for: url) {
      guard request == requestToken else { return }
      Log.player.debug("cache hit for url: \(url, privacy: .public)")
      queue = [track]
      index = -1
      pathCache[track.id] = path
      if !hasTitle {
        Task { await self.refreshCachedTitle(url: url, id: track.id) }
      }
      await playIndex(0, startAt: startAt)
      return
    }

    setStatus(.resolving)
    let resolution: ResolvedTracks
    do {
      resolution = try await ytdlp.resolve(url: url)
    } catch {
      guard request == requestToken else { return }
      lastError = String(describing: error)
      setStatus(.failed)
      return
    }
    observeMetadataUpdates(resolution.metadataUpdates)
    libraryRevision += 1
    guard request == requestToken else { return }
    queue = resolution.tracks
    index = -1
    guard !queue.isEmpty else {
      setStatus(.idle)
      return
    }
    // A timecode in the pasted URL applies to the first track only.
    await playIndex(0, startAt: startAt)
  }

  /// Resolve `url` and append its tracks, leaving playback alone; starts
  /// playing the first appended track only if nothing is selected yet.
  /// Returns how many tracks were added.
  @discardableResult
  func add(url: String) async -> Int {
    requestToken += 1
    let request = requestToken
    lastError = nil
    if let (track, path, _) = await cachedTrack(for: url) {
      guard request == requestToken else { return 0 }
      let startFrom = queue.count
      queue.append(track)
      pathCache[track.id] = path
      if index < 0 {
        await playIndex(startFrom)
      }
      return 1
    }

    let resolution: ResolvedTracks
    do {
      resolution = try await ytdlp.resolve(url: url)
    } catch {
      guard request == requestToken else { return 0 }
      lastError = String(describing: error)
      return 0
    }
    observeMetadataUpdates(resolution.metadataUpdates)
    libraryRevision += 1
    guard request == requestToken else { return 0 }
    let tracks = resolution.tracks
    guard !tracks.isEmpty else { return 0 }
    let startFrom = queue.count
    queue.append(contentsOf: tracks)
    // index < 0 means nothing has been selected, so kick off the first new track.
    if index < 0 {
      await playIndex(startFrom)
    }
    return tracks.count
  }

  /// Play queue[i]. Supersedes any in-flight download/decode (token
  /// semantics: a stale download must never start audio). On failure the
  /// track is skipped; the queue is declared dead (status .failed) only when
  /// consecutive failures reach queue.count. On success, preloads the next
  /// 2 tracks in the background.
  func playIndex(_ i: Int, startAt: TimeInterval = 0) async {
    guard queue.indices.contains(i) else { return }
    requestToken += 1
    playToken += 1
    let token = playToken
    let track = queue[i]
    index = i
    downloadProgress = nil
    stopPositionTicking()
    currentTime = 0
    duration = 0
    updateNowPlayingPosition()
    // Stop the outgoing track now, before any download/decode: otherwise it
    // keeps playing under the new track's UI state, and its onEnded could
    // even auto-advance past the user's selection.
    await audioEngine.stop()

    let path: URL
    if let cached = pathCache[track.id] {
      Log.player.debug("download cache hit: \(cached.path, privacy: .public)")
      // No download runs on a cache hit, so supersede any in-flight one
      // (its generation would otherwise stay current and keep emitting progress).
      cancelDownloads()
      await ytdlp.cancelActiveDownload()
      path = cached
    } else {
      setStatus(.downloading)
      Log.player.debug("download start: \(track.webpageURL.absoluteString, privacy: .public)")
      do {
        path = try await downloadTrack(track, background: false).task.value
      } catch {
        // A newer selection superseded this download; that's expected,
        // not a user-facing error. Anything else means this track is
        // unplayable, so skip to the next instead of stalling.
        guard token == playToken else { return }
        if (error as? YtDlpError) == .superseded {
          do {
            path = try await downloadTrack(track, background: false).task.value
          } catch {
            guard token == playToken else { return }
            if (error as? YtDlpError) != .superseded {
              lastError = String(describing: error)
            }
            Log.player.warning("download failed, skipping: \(track.title, privacy: .public)")
            await skipFailedTrack(failedIndex: i, token: token)
            return
          }
        } else {
          lastError = String(describing: error)
          Log.player.warning("download failed, skipping: \(track.title, privacy: .public)")
          await skipFailedTrack(failedIndex: i, token: token)
          return
        }
      }
      Log.player.debug("download ready: \(path.path, privacy: .public)")
    }
    guard token == playToken else { return }  // a newer selection superseded this one
    downloadProgress = nil
    setStatus(.decoding)
    do {
      try audioEngine.play(fileURL: path, startAt: startAt)
    } catch {
      guard token == playToken else { return }
      pathCache.removeValue(forKey: track.id)
      lastError = String(describing: error)
      Log.player.warning("decode failed, skipping: \(track.title, privacy: .public)")
      await skipFailedTrack(failedIndex: i, token: token)
      return
    }
    consecutiveFailures = 0  // a track played; the queue isn't dead
    duration = audioEngine.duration
    setStatus(.playing)
    await updateNowPlayingTrack(playToken: token)
    guard token == playToken else { return }
    Task { await self.preloadLookahead(anchorIndex: i, token: token) }
  }

  /// Toggle play/pause. When idle with a current track, restarts it from 0.
  func togglePause() async {
    if status == .idle, currentTrack != nil {
      if await audioEngine.restart() {
        consecutiveFailures = 0
        duration = audioEngine.duration
        setStatus(.playing)
      } else {
        // The engine unloaded the file (queue ended); replay from the cache.
        await playIndex(index)
      }
      return
    }
    // Only a playing/paused track can be toggled; ignore when idle (nothing
    // loaded, or the queue ended) or mid-load.
    guard status == .playing || status == .paused else { return }
    let paused = await audioEngine.togglePause()
    setStatus(paused ? .paused : .playing)
  }

  /// Auto-advance/next: honors repeatMode (.one replays, .queue wraps).
  func next() async {
    await advance(fromEnded: false)
  }

  /// Restart if >2s in (or no previous track), else go to the previous track.
  func prev() async {
    let hasPrevious = index - 1 >= 0
    let canRestart = status == .playing || status == .paused
    if canRestart,
      !hasPrevious || audioEngine.currentTime > Self.prevRestartSeconds,
      await audioEngine.restart()
    {
      consecutiveFailures = 0
      duration = audioEngine.duration
      setStatus(.playing)
      return
    }
    if hasPrevious { await playIndex(index - 1) }
  }

  /// Wrap-around skip, ignoring repeat mode.
  func skipNext() async {
    guard !queue.isEmpty else { return }
    await playIndex(index + 1 < queue.count ? index + 1 : 0)
  }

  func skipPrev() async {
    guard !queue.isEmpty else { return }
    await playIndex(index - 1 >= 0 ? index - 1 : queue.count - 1)
  }

  func seek(to time: TimeInterval) async {
    await audioEngine.seek(to: time)
    refreshPosition()
    updateNowPlayingPosition()
  }

  func seek(by delta: TimeInterval) async {
    await seek(to: currentTime + delta)
  }

  /// Empty the queue and stop playback, including in-flight downloads.
  func clear() async {
    requestToken += 1
    playToken += 1  // a stale in-flight download won't start audio
    cancelDownloads()
    await ytdlp.cancelActiveDownload()
    await audioEngine.stop()
    queue = []
    index = -1
    duration = 0
    currentTime = 0
    consecutiveFailures = 0
    downloadProgress = nil
    setStatus(.idle)
    nowPlaying.clear()
  }

  func toggleRepeat() {
    repeatMode = repeatMode == .off ? .queue : (repeatMode == .queue ? .one : .off)
  }

  func toggleMute() {
    isMuted.toggle()
  }

  // MARK: VU metering

  /// Per-channel level 0...1 with fast-attack/slow-release ballistics over a
  /// kick-band (lowpass ~120 Hz) tap. Poll from the render loop (~60 fps).
  func levels() -> (l: Float, r: Float) {
    audioEngine.levels()
  }

  // MARK: artwork

  /// Local file URL of the cached cover art for a track, downloading it into
  /// the app cache (`<id>_thumb.<ext>`) on first request. nil when the track
  /// has no thumbnail or the fetch fails. Shared with the Now Playing cover.
  func artworkURL(for track: Track) async -> URL? {
    await ytdlp.artworkURL(for: track)
  }

  func librarySnapshot() async -> LibrarySnapshot {
    await ytdlp.librarySnapshot()
  }

  func playLibraryTracks(_ tracks: [Track]) async {
    guard !tracks.isEmpty else { return }
    requestToken += 1
    queue = tracks
    index = -1
    await playIndex(0)
  }

  func addLibraryTracks(_ tracks: [Track]) {
    queue.append(contentsOf: tracks)
  }

  func removeLibrarySong(id: String) async throws {
    downloadTasks[id]?.task.cancel()
    if downloadTasks[id] != nil {
      await ytdlp.cancelActiveDownload()
    }
    do {
      try await ytdlp.removeLibrarySong(id: id)
      pathCache.removeValue(forKey: id)
      lastError = nil
    } catch {
      lastError = String(describing: error)
      throw error
    }
  }

  func removeLibraryPlaylist(id: String) async throws {
    do {
      try await ytdlp.removeLibraryPlaylist(id: id)
      lastError = nil
    } catch {
      lastError = String(describing: error)
      throw error
    }
  }

  // MARK: cache maintenance (settings UI)

  /// Total bytes of cached audio and artwork in the app cache directory.
  func cacheSize() async -> UInt64 {
    await ytdlp.cacheSize()
  }

  /// Delete cached media without deleting library metadata. The playing track
  /// keeps its in-memory buffer; queued tracks re-download on next play.
  func purgeCache() async throws {
    cancelDownloads()
    await ytdlp.cancelActiveDownload()
    try await ytdlp.purgeCache()
    // Drop the in-memory path cache so queued tracks re-download instead of
    // pointing at deleted files. The track playing now keeps its decoded
    // buffer inside the audio engine and isn't interrupted.
    pathCache.removeAll()
  }

  // MARK: - private helpers

  private func setStatus(_ newStatus: PlayerStatus) {
    status = newStatus
    if newStatus == .playing {
      startPositionTicking()
    } else {
      stopPositionTicking()
    }
    updateNowPlayingPosition()
  }

  private func refreshPosition() {
    currentTime = audioEngine.currentTime
  }

  private func startPositionTicking() {
    positionTask?.cancel()
    positionTask = Task { [weak self] in
      while let self, !Task.isCancelled {
        self.refreshPosition()
        try? await Task.sleep(for: .milliseconds(100))
      }
    }
  }

  private func stopPositionTicking() {
    positionTask?.cancel()
    positionTask = nil
    refreshPosition()
  }

  private func updateNowPlayingPosition() {
    nowPlaying.updatePosition(elapsed: currentTime, speed: speed, isPlaying: status == .playing)
  }

  private func updateNowPlayingTrack(playToken token: Int? = nil) async {
    guard let track = currentTrack else {
      nowPlaying.clear()
      return
    }
    let artwork = await ytdlp.artworkURL(for: track)
    if let token, token != playToken { return }
    guard currentTrack?.id == track.id else { return }
    nowPlaying.setTrack(
      track, artworkURL: artwork, duration: duration, elapsed: currentTime, speed: speed,
      isPlaying: status == .playing)
  }

  private func observeMetadataUpdates(_ updates: AsyncStream<Track>) {
    Task { [weak self] in
      for await track in updates {
        guard let self else { return }
        for index in queue.indices where queue[index].id == track.id {
          queue[index] = track
        }
        libraryRevision += 1
        if currentTrack?.id == track.id { await updateNowPlayingTrack() }
      }
    }
  }

  private func refreshCachedTitle(url: String, id: String) async {
    guard let resolution = try? await ytdlp.resolve(url: url) else { return }
    libraryRevision += 1
    let tracks = resolution.tracks
    guard let track = tracks.first(where: { $0.id == id }) ?? tracks.first else { return }
    guard queue.first?.id == id else { return }
    queue[0].title = track.title
    queue[0].artist = track.artist
    if index == 0 { await updateNowPlayingTrack() }
  }

  private func cachedTrack(for url: String) async -> (Track, URL, Bool)? {
    guard let parsedURL = URL(string: url) else { return nil }
    let cachedByID: CachedAudioInfo?
    if let id = URLParsing.videoID(from: url) {
      cachedByID = await ytdlp.cachedAudio(id: id)
    } else {
      cachedByID = nil
    }
    let cachedByURL = cachedByID == nil ? await ytdlp.cachedAudio(url: url) : nil
    let cached = cachedByID ?? cachedByURL
    guard let cached else { return nil }
    let artist = cached.artist ?? YtDlpClient.inferredArtist(for: .init(title: cached.title))
    let title = YtDlpClient.titleWithoutArtist(cached.title ?? "cached track", artist: artist)
    let track = Track(
      id: cached.id, title: title, artist: artist,
      webpageURL: cached.webpageURL ?? parsedURL, thumbnailURL: cached.thumbnailURL,
      duration: cached.duration)
    return (track, cached.path, cached.title != nil)
  }

  /// A track failed to download or decode (e.g. age-gated video yt-dlp can't
  /// fetch without auth). Skip to the next one instead of stalling on
  /// .failed; give up only once the whole queue has proved unplayable.
  private func skipFailedTrack(failedIndex: Int, token: Int) async {
    guard token == playToken else { return }
    await audioEngine.stop()
    consecutiveFailures += 1
    let nextIndex: Int
    if failedIndex + 1 < queue.count {
      nextIndex = failedIndex + 1
    } else if repeatMode == .queue {
      nextIndex = 0
    } else {
      nextIndex = -1
    }
    if nextIndex < 0 || consecutiveFailures >= queue.count {
      consecutiveFailures = 0
      duration = 0
      setStatus(.failed)
      return
    }
    await playIndex(nextIndex)
  }

  private func advance(fromEnded: Bool) async {
    if fromEnded, repeatMode == .one, index >= 0 {
      await playIndex(index)
    } else if index + 1 < queue.count {
      await playIndex(index + 1)
    } else if repeatMode == .queue, !queue.isEmpty {
      await playIndex(0)
    } else {
      await audioEngine.stop()
      duration = 0
      setStatus(.idle)  // reached the end → nothing playing
    }
  }

  private func downloadTrack(_ track: Track, background: Bool) -> DownloadHandle {
    if let existing = downloadTasks[track.id] {
      if !background { progressDownloadID = existing.id }
      return existing
    }

    let id = UUID()
    activeDownloadIDs.insert(id)
    isDownloading = true
    if !background || progressDownloadID == nil {
      progressDownloadID = id
      downloadProgress = nil
    }

    let task = Task<URL, Error> {
      defer { self.finishDownload(id: id, trackID: track.id) }
      let path = try await ytdlp.download(url: track.webpageURL.absoluteString, id: track.id) {
        [weak self] percent in
        await self?.updateDownloadProgress(percent, id: id)
      }
      try Task.checkCancellation()
      self.pathCache[track.id] = path
      return path
    }
    let handle = DownloadHandle(id: id, task: task)
    downloadTasks[track.id] = handle
    return handle
  }

  private func updateDownloadProgress(_ percent: Double, id: UUID) {
    guard activeDownloadIDs.contains(id), progressDownloadID == id else { return }
    downloadProgress = percent
  }

  private func finishDownload(id: UUID, trackID: String) {
    guard activeDownloadIDs.remove(id) != nil else { return }
    downloadTasks.removeValue(forKey: trackID)
    if progressDownloadID == id {
      progressDownloadID = activeDownloadIDs.first
      downloadProgress = nil
    }
    if activeDownloadIDs.isEmpty {
      progressDownloadID = nil
      downloadProgress = nil
    }
    isDownloading = !activeDownloadIDs.isEmpty
  }

  private func cancelDownloads() {
    for handle in downloadTasks.values {
      handle.task.cancel()
    }
    downloadTasks.removeAll()
    activeDownloadIDs.removeAll()
    progressDownloadID = nil
    downloadProgress = nil
    isDownloading = false
  }

  private func preloadLookahead(anchorIndex: Int, token: Int) async {
    for offset in 1...Self.lookaheadCount {
      guard token == playToken else { return }
      let idx = anchorIndex + offset
      guard queue.indices.contains(idx) else { continue }
      let track = queue[idx]
      guard pathCache[track.id] == nil else { continue }
      do {
        _ = try await downloadTrack(track, background: true).task.value
      } catch {
        // A foreground selection supersedes background preloads by design.
        if token == playToken {
          Log.player.debug("lookahead skipped: \(String(describing: error), privacy: .public)")
        }
        return
      }
    }
  }
}

// MARK: - Now Playing command routing (media keys / Control Center)

extension PlayerModel: NowPlayingDelegate {
  func nowPlayingDidRequestPlay() {
    guard status != .playing else { return }
    Task { await self.togglePause() }
  }

  func nowPlayingDidRequestPause() {
    guard status == .playing else { return }
    Task { await self.togglePause() }
  }

  func nowPlayingDidRequestTogglePlayPause() {
    Task { await self.togglePause() }
  }

  func nowPlayingDidRequestNext() {
    Task { await self.skipNext() }
  }

  func nowPlayingDidRequestPrevious() {
    Task { await self.skipPrev() }
  }

  func nowPlayingDidRequestSeek(to time: TimeInterval) {
    Task { await self.seek(to: time) }
  }

  func nowPlayingDidRequestSkip(by delta: TimeInterval) {
    Task { await self.seek(by: delta) }
  }
}
