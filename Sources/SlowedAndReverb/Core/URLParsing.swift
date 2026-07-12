import Foundation

// MARK: - URL helpers (pure, unit-tested)

enum URLParsing {
  private static let hmsPattern = /(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?/.ignoresCase()
  private static let videoIDPattern = /[A-Za-z0-9_-]{11}/

  /// Seconds to start at, from a YouTube `t`/`start` param (`90`, `1m30s`, …).
  static func startSeconds(from url: String) -> TimeInterval {
    guard let components = URLComponents(string: url) else { return 0 }
    let items = components.queryItems ?? []
    guard
      let raw = (items.first { $0.name == "t" }?.value)
        ?? (items.first { $0.name == "start" }?.value),
      !raw.isEmpty
    else { return 0 }
    if raw.allSatisfy(\.isNumber) { return Double(raw) ?? 0 }

    guard let (_, h, m, s) = raw.wholeMatch(of: hmsPattern)?.output else { return 0 }
    func seconds(_ group: Substring?) -> Double { group.flatMap { Double($0) } ?? 0 }
    return seconds(h) * 3600 + seconds(m) * 60 + seconds(s)
  }

  /// True for any http(s) URL; gates paste-to-add. Host is not checked;
  /// yt-dlp resolves far more than YouTube.
  static func looksLikeURL(_ text: String) -> Bool {
    guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
      return false
    }
    return url.scheme == "http" || url.scheme == "https"
  }

  /// The 11-char YouTube video id for watch/youtu.be/shorts/embed/live URLs,
  /// nil for playlists (`list=` present) or anything else.
  static func videoID(from url: String) -> String? {
    guard let components = URLComponents(string: url), let host = components.host else {
      return nil
    }
    if components.queryItems?.contains(where: { $0.name == "list" }) == true { return nil }

    let host2 = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    let pathComponents = components.path.split(separator: "/").map(String.init)

    let id: String?
    if host2 == "youtu.be" {
      id = pathComponents.first
    } else if host2.hasSuffix("youtube.com"), components.path == "/watch" {
      id = components.queryItems?.first(where: { $0.name == "v" })?.value
    } else if host2.hasSuffix("youtube.com"), pathComponents.count >= 2,
      ["shorts", "embed", "live"].contains(pathComponents[0])
    {
      id = pathComponents[1]
    } else {
      id = nil
    }

    guard let id, id.wholeMatch(of: videoIDPattern) != nil else { return nil }
    return id
  }
}
