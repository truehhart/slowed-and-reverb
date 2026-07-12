import AVFoundation
import Foundation
import Synchronization

/// Per-channel kick-band level: `process` runs on the audio render thread,
/// `snapshot` on MainActor. Only the shared target values need the lock;
/// the lowpass filter state is render-thread-only.
nonisolated final class LevelMeterState: @unchecked Sendable {
  private let targets = Mutex<(l: Float, r: Float)>((0, 0))
  private var lowpassL: Float = 0
  private var lowpassR: Float = 0

  private let kickHz: Double = 120
  private let makeupGain: Float = 5

  func process(buffer: AVAudioPCMBuffer) {
    guard let channelData = buffer.floatChannelData else { return }
    let frameLength = Int(buffer.frameLength)
    guard frameLength > 0 else { return }
    let channelCount = Int(buffer.format.channelCount)
    let sampleRate = buffer.format.sampleRate
    guard sampleRate > 0 else { return }
    let alpha = Float(1 - exp(-2 * Double.pi * kickHz / sampleRate))

    let targetLeft = softKnee(
      rms(channelData[0], frameLength: frameLength, alpha: alpha, lowpass: &lowpassL))
    let targetRight: Float
    if channelCount > 1 {
      targetRight = softKnee(
        rms(channelData[1], frameLength: frameLength, alpha: alpha, lowpass: &lowpassR))
    } else {
      targetRight = targetLeft
    }

    targets.withLock { $0 = (targetLeft, targetRight) }
  }

  private func rms(
    _ data: UnsafeMutablePointer<Float>, frameLength: Int, alpha: Float, lowpass: inout Float
  ) -> Float {
    var sumSquares: Float = 0
    var lp = lowpass
    for i in 0..<frameLength {
      lp += alpha * (data[i] - lp)
      sumSquares += lp * lp
    }
    lowpass = lp
    return sqrt(sumSquares / Float(frameLength)) * makeupGain
  }

  // Approaches 1 asymptotically instead of hard-clamping, so a dense mix
  // floats near the top with headroom instead of pinning flat.
  private func softKnee(_ g: Float) -> Float {
    1 - exp(-g)
  }

  func snapshot() -> (Float, Float) {
    targets.withLock { ($0.l, $0.r) }
  }
}
