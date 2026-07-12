import AppKit
import SwiftUI

struct ReelView: View {
  let period: TimeInterval
  let playing: Bool

  @State private var roll = ReelRoll()
  private static let size: CGFloat = 100
  private static let faceOffsetY: CGFloat = 1.6
  private static let face =
    Bundle.module.url(forResource: "tape-reel-grunge", withExtension: "jpg")
    .flatMap(NSImage.init(contentsOf:)) ?? NSImage(size: NSSize(width: size, height: size))

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playing)) { timeline in
      Image(nsImage: Self.face)
        .resizable()
        .interpolation(.high)
        .scaledToFit()
        .offset(y: Self.faceOffsetY)
        .clipShape(Circle())
        .rotationEffect(
          .degrees(roll.angle(now: timeline.date, playing: playing, period: period)))
    }
    .shadow(color: .black.opacity(0.85), radius: 5, y: 3)
    .frame(width: Self.size, height: Self.size)
  }
}

private final class ReelRoll {
  private var accumulated: TimeInterval = 0
  private var lastTick: Date?

  func angle(now: Date, playing: Bool, period: TimeInterval) -> Double {
    if playing {
      if let lastTick {
        accumulated += min(max(now.timeIntervalSince(lastTick), 0), 1)
      }
      lastTick = now
    } else {
      lastTick = nil
    }
    return accumulated / period * 360
  }
}
