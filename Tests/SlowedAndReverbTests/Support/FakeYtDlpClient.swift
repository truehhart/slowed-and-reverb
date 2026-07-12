import Foundation

@testable import SlowedAndReverb

/// YtDlpClientProtocol fake, driven entirely by MainActor test code (no real
/// process/network), so PlayerModel's queue logic is testable without yt-dlp.
final class FakeYtDlpClient: YtDlpClientProtocol, @unchecked Sendable {
  var resolveHandler: ((String) throws -> [Track])?
  var asyncResolveHandler: ((String) async throws -> [Track])?
  var downloadHandler: ((String, String) async throws -> URL)?
  var cachedAudioByID: [String: CachedAudioInfo] = [:]

  private(set) var resolveCalls: [String] = []
  private(set) var downloadCalls: [(url: String, id: String)] = []
  private(set) var cancelCount = 0

  func resolve(url: String) async throws -> [Track] {
    resolveCalls.append(url)
    if let asyncResolveHandler { return try await asyncResolveHandler(url) }
    guard let resolveHandler else { return [] }
    return try resolveHandler(url)
  }

  func download(url: String, id: String, progress: @escaping @Sendable (Double) -> Void)
    async throws -> URL
  {
    downloadCalls.append((url, id))
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
