import AppKit
import SwiftUI

/// Global keyboard behavior, matching the web original: space/K play-pause,
/// J/← back 5s, L/→ forward 5s, ↑/↓ volume, and paste-to-add (⌘V outside a
/// text field drops a link straight onto the queue). Skipped entirely while
/// a text field is being edited.
final class KeyEventMonitor {
  private var monitor: Any?

  init(player: PlayerModel, queueBox: QueueBoxModel, statusLine: StatusLine) {
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      Self.handle(event, player: player, queueBox: queueBox, statusLine: statusLine)
    }
  }

  func uninstall() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
  }

  private static func handle(
    _ event: NSEvent, player: PlayerModel, queueBox: QueueBoxModel, statusLine: StatusLine
  ) -> NSEvent? {
    let seekStep: TimeInterval = 5
    let volumeStep = 0.05

    // typing wins: leave events alone while any text field is active
    if NSApp.keyWindow?.firstResponder is NSTextView { return event }

    if event.modifierFlags.contains(.command) {
      guard event.charactersIgnoringModifiers == "v" else { return event }
      guard
        let text = NSPasteboard.general.string(forType: .string)?
          .trimmingCharacters(in: .whitespacesAndNewlines),
        URLParsing.looksLikeURL(text)
      else { return event }
      queueBox.urlText = text
      Task { await queueBox.submit(.add, player: player, status: statusLine) }
      return nil
    }
    guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else {
      return event
    }

    switch event.charactersIgnoringModifiers {
    case " ", "k":
      Task { await player.togglePause() }
      return nil
    case "j":
      player.seek(by: -seekStep)
      return nil
    case "l":
      player.seek(by: seekStep)
      return nil
    default:
      break
    }

    switch event.keyCode {
    case 123:  // ←
      player.seek(by: -seekStep)
      return nil
    case 124:  // →
      player.seek(by: seekStep)
      return nil
    case 126:  // ↑
      player.volume = min(1, player.volume + volumeStep)
      return nil
    case 125:  // ↓
      player.volume = max(0, player.volume - volumeStep)
      return nil
    default:
      return event
    }
  }
}
