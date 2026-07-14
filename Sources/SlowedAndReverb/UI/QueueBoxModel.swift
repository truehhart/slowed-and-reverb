import Foundation
import Observation

/// State for the add row. Lives above the queue module so paste-to-add can
/// feed the same submit path and busy feedback as typing in the field.
@Observable
final class QueueBoxModel {
  var urlText = ""
  private(set) var isSubmitting = false
  /// Toggles once per landed add; the add row animates a one-shot glow off it.
  private(set) var flashPulse = 0

  func submit(player: PlayerModel, status: StatusLine) async {
    guard !isSubmitting else { return }
    let url = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard URLParsing.looksLikeURL(url) else { return }
    isSubmitting = true
    status.show("adding…")
    defer { isSubmitting = false }

    let added = await player.add(url: url)
    if let error = player.lastError {
      status.show(error, isError: true)
      return
    }
    urlText = ""
    flashPulse += 1
    // Report just what this submit added (not the cumulative queue length).
    if added > 0 {
      status.flash("queued \(added) track\(added == 1 ? "" : "s")")
    } else {
      status.clear()
    }
  }
}
