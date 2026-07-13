import Foundation

/// Seam between PlayerModel and the yt-dlp process so queue/download logic is
/// testable without a network call or a real subprocess. Every requirement is
/// `async`: the production client is an actor, so all its filesystem/process
/// I/O runs off the main actor.
protocol YtDlpClientProtocol: Sendable {
  func resolve(url: String) async throws -> [Track]
  func download(url: String, id: String, progress: @escaping @Sendable (Double) -> Void)
    async throws -> URL
  func cancelActiveDownload() async
  func cachedAudio(id: String) async -> CachedAudioInfo?
  func cachedAudio(url: String) async -> CachedAudioInfo?
  func librarySnapshot() async -> LibrarySnapshot
  func removeLibrarySong(id: String) async throws
  func removeLibraryPlaylist(id: String) async throws
  func artworkURL(for track: Track) async -> URL?
  func cacheSize() async -> UInt64
  func purgeCache() async throws
}
