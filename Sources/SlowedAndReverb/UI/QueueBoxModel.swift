import Foundation
import Observation

/// State for the add-row / import pair. Lives above the queue module so
/// paste-to-add (a global shortcut) can feed the same submit path and busy
/// feedback as typing in the field.
@Observable
final class QueueBoxModel {
  enum Mode {
    case add, replace
  }

  var urlText = ""
  private(set) var isSubmitting = false
  /// Toggles once per landed add; the add row animates a one-shot glow off it.
  private(set) var flashPulse = 0

  func submit(_ mode: Mode, player: PlayerModel, status: StatusLine) async {
    guard !isSubmitting else { return }
    let url = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !url.isEmpty else { return }
    isSubmitting = true
    status.show(mode == .replace ? "loading…" : "adding…")
    defer { isSubmitting = false }

    let added: Int
    switch mode {
    case .replace:
      await player.load(url: url)
      added = player.queue.count
    case .add:
      added = await player.add(url: url)
    }
    if let error = player.lastError {
      status.show(error, isError: true)
      return
    }
    urlText = ""
    if mode == .add { flashPulse += 1 }
    // Report just what this submit added (not the cumulative queue length).
    if added > 0 {
      status.flash("queued \(added) track\(added == 1 ? "" : "s")")
    } else {
      status.clear()
    }
  }
}
