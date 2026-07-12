import SwiftUI

/// Now-playing title: shows whole when it fits; when it overflows, glides
/// back and forth (~45pt/s with holds at each end), like the CSS marquee.
struct MarqueeText: View {
  let text: String
  let font: Font
  let color: Color

  @State private var textWidth: CGFloat = 0
  @State private var containerWidth: CGFloat = 0

  var body: some View {
    let overflow = max(0, textWidth - containerWidth)
    Group {
      if overflow > 4 {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
          label.offset(x: -overflow * phase(at: timeline.date, overflow: overflow))
        }
      } else {
        label
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .clipped()
    .onGeometryChange(
      for: CGFloat.self, of: { $0.size.width }, action: { containerWidth = $0 }
    )
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
    let cycle = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: leg * 2)
    let forward = cycle < leg
    let t = (forward ? cycle : cycle - leg) / leg
    let glide = min(max((t - 0.22) / 0.56, 0), 1)
    let eased = glide * glide * (3 - 2 * glide)
    return CGFloat(forward ? eased : 1 - eased)
  }
}
