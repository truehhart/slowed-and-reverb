import SwiftUI

/// Shows the whole label when it fits; when it overflows, glides back and forth.
struct MarqueeText: View {
  let text: String
  let font: Font
  let color: Color
  var moves = true
  var startsImmediately = false

  @State private var textWidth: CGFloat = 0
  @State private var containerWidth: CGFloat = 0
  @State private var movementStartedAt = Date()

  var body: some View {
    let overflow = max(0, textWidth - containerWidth)
    // A hidden single-space label reserves the line height while staying
    // flexible in width, so the fixed-size measuring label (in the overlay)
    // can never expand this view past the width its container hands it.
    Text(" ")
      .font(font)
      .lineLimit(1)
      .hidden()
      .frame(maxWidth: .infinity, alignment: .leading)
      .overlay(alignment: .leading) {
        if moves, overflow > 4 {
          TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            label.offset(x: -overflow * phase(at: timeline.date, overflow: overflow))
          }
        } else {
          label
        }
      }
      .clipped()
      .onGeometryChange(
        for: CGFloat.self, of: { $0.size.width }, action: { containerWidth = $0 }
      )
      .onChange(of: moves) { _, nowMoves in
        if nowMoves { movementStartedAt = Date() }
      }
      .help(text)
  }

  private var label: some View {
    Text(text)
      .font(font)
      .foregroundStyle(color)
      .lineLimit(1)
      .fixedSize()
      .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { textWidth = $0 })
  }

  /// 0…1 shift: hold 22% at each end, ease between, alternating direction.
  private func phase(at date: Date, overflow: CGFloat) -> CGFloat {
    let leg = max(6, Double(overflow) / 45 + 4)
    let initialHold = startsImmediately ? leg * 0.22 : 0
    let elapsed = max(0, date.timeIntervalSince(movementStartedAt)) + initialHold
    let cycle = elapsed.truncatingRemainder(dividingBy: leg * 2)
    let forward = cycle < leg
    let t = (forward ? cycle : cycle - leg) / leg
    let glide = min(max((t - 0.22) / 0.56, 0), 1)
    let eased = glide * glide * (3 - 2 * glide)
    return CGFloat(forward ? eased : 1 - eased)
  }
}
