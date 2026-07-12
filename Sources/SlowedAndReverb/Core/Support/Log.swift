import Foundation
import os

/// Categorized loggers, one per subsystem area. Bundle id fallback mirrors
/// YtDlpClient's cache-dir fallback so `swift run` and the bundled app agree.
nonisolated enum Log {
  private static let subsystem = Bundle.main.bundleIdentifier ?? "com.truehhart.slowed-and-reverb"

  static let app = Logger(subsystem: subsystem, category: "app")
  static let player = Logger(subsystem: subsystem, category: "player")
  static let audio = Logger(subsystem: subsystem, category: "audio")
  static let ytdlp = Logger(subsystem: subsystem, category: "ytdlp")
  static let updater = Logger(subsystem: subsystem, category: "updater")
}
