import Synchronization

/// A promise-like handoff for tests that need a download to stay pending
/// until explicitly resolved (mirrors the old `deferred<T>()` test helper).
final class Deferred<T: Sendable>: @unchecked Sendable {
  private struct State {
    var continuation: CheckedContinuation<T, Error>?
    var resolvedValue: T?
  }

  private let state = Mutex<State>(State())

  var value: T {
    get async throws {
      try await withCheckedThrowingContinuation { cont in
        state.withLock { s in
          if let resolvedValue = s.resolvedValue {
            cont.resume(returning: resolvedValue)
          } else {
            s.continuation = cont
          }
        }
      }
    }
  }

  func resolve(_ value: T) {
    let cont: CheckedContinuation<T, Error>? = state.withLock { s in
      s.resolvedValue = value
      let cont = s.continuation
      s.continuation = nil
      return cont
    }
    cont?.resume(returning: value)
  }
}
