import AVFoundation
import Foundation
import Synchronization

/// Per-channel visual level: `process` runs on the audio render thread and
/// `snapshot` on MainActor. Envelope state is render-thread-only.
nonisolated final class LevelMeterState: @unchecked Sendable {
  private let levels = Mutex<(l: Float, r: Float)>((0, 0))
  private var displayL: Float = 0
  private var displayR: Float = 0

  private let rmsWeight: Float = 0.3
  private let peakWeight: Float = 0.7
  private let makeupGain: Float = 2
  private let attackSeconds: Float = 0.012
  private let releaseSeconds: Float = 0.12

  func process(buffer: AVAudioPCMBuffer) {
    guard let channelData = buffer.floatChannelData else { return }
    let frameLength = Int(buffer.frameLength)
    guard frameLength > 0 else { return }
    let channelCount = Int(buffer.format.channelCount)
    let sampleRate = buffer.format.sampleRate
    guard sampleRate > 0 else { return }
    let duration = Float(Double(frameLength) / sampleRate)

    displayL = nextLevel(
      data: channelData[0], frameLength: frameLength, duration: duration, current: displayL)
    if channelCount > 1 {
      displayR = nextLevel(
        data: channelData[1], frameLength: frameLength, duration: duration, current: displayR)
    } else {
      displayR = displayL
    }

    levels.withLock { $0 = (displayL, displayR) }
  }

  private func nextLevel(
    data: UnsafeMutablePointer<Float>, frameLength: Int, duration: Float, current: Float
  ) -> Float {
    var sumSquares: Float = 0
    var peak: Float = 0
    for frame in 0..<frameLength {
      let sample = data[frame]
      guard sample.isFinite else { continue }
      sumSquares += sample * sample
      peak = max(peak, abs(sample))
    }

    let rms = sqrt(sumSquares / Float(frameLength))
    let signal = rmsWeight * rms + peakWeight * peak
    let target = 1 - exp(-makeupGain * signal)
    let envelopeSeconds = target > current ? attackSeconds : releaseSeconds
    let rate = 1 - exp(-duration / envelopeSeconds)
    return current + rate * (target - current)
  }

  func snapshot() -> (Float, Float) {
    levels.withLock { ($0.l, $0.r) }
  }
}
