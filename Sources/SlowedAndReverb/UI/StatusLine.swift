import Foundation
import Observation

/// The deck's status readout: persistent messages (errors, update progress)
/// and transient flashes ("queued 12 tracks") that clear themselves after a
/// few seconds unless a newer message replaced them.
@Observable
final class StatusLine {
  private(set) var message: String?
  private(set) var isError = false

  private var flashTask: Task<Void, Never>?

  func show(_ text: String, isError: Bool = false) {
    flashTask?.cancel()
    message = text.isEmpty ? nil : text
    self.isError = isError
  }

  func flash(_ text: String) {
    show(text)
    flashTask = Task {
      try? await Task.sleep(for: .seconds(4))
      guard !Task.isCancelled, message == text else { return }
      message = nil
    }
  }

  func clear() {
    show("")
  }
}
