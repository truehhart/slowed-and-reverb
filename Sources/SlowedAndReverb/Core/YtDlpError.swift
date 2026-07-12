enum YtDlpError: Error, Equatable, CustomStringConvertible {
  case launchFailed(String)
  case failed(String)
  case superseded
  case invalidResponse
  case noPlayableTracks
  case noOutputPath

  /// "superseded" is a sentinel for the caller (a stale selection lost the
  /// race), never a user-facing error.
  var description: String {
    switch self {
    case .launchFailed(let m): return "failed to launch bundled yt-dlp: \(m)"
    case .failed(let m): return m.isEmpty ? "yt-dlp failed" : m
    case .superseded: return "superseded"
    case .invalidResponse: return "could not parse yt-dlp output"
    case .noPlayableTracks: return "no playable tracks found"
    case .noOutputPath: return "yt-dlp did not report an output path"
    }
  }
}
