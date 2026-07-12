import SwiftUI

/// L/R analog-style level meters: a finely graduated tick scale whose ticks
/// light up with the kick-band level. 0 dBFS is the maximum (the rightmost
/// tick); the ticks approaching it run red as a peak warning. Only the meter
/// face refreshes on the render clock; labels and frame are static.
struct VUMeterView: View {
  @Environment(PlayerModel.self) private var player

  private let labels = ["-20", "-10", "-7", "-5", "-3", "-1", "0"]

  var body: some View {
    let playing = player.status == .playing
    VStack(spacing: 8) {
      row(label: "L", playing: playing) { $0.l }
      row(label: "R", playing: playing) { $0.r }
    }
    .padding(.vertical, 10)
    .padding(.horizontal, 10)
    .railBackground(depth: 7)
  }

  private func row(
    label: String, playing: Bool, level: @escaping ((l: Float, r: Float)) -> Float
  ) -> some View {
    HStack(spacing: 8) {
      Text(label)
        .font(Theme.mono(11.8, bold: true))
        .foregroundStyle(Theme.label)
        .frame(width: 14, alignment: .leading)
      VStack(spacing: 3) {
        scale
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playing)) { _ in
          Meter(level: playing ? level(player.levels()) : 0, labelCount: labels.count)
            .frame(height: 15)
        }
      }
      .frame(maxWidth: .infinity)
    }
  }

  private var scale: some View {
    HStack(spacing: 0) {
      ForEach(labels, id: \.self) { text in
        Text(text)
          .font(Theme.mono(8.1, bold: true))
          .monospacedDigit()
          .foregroundStyle(text == "0" ? Theme.burgundy : Theme.amber)
          .frame(maxWidth: .infinity)
      }
    }
  }
}

/// The graduated meter face for one channel.
private struct Meter: View {
  let level: Float
  let labelCount: Int

  var body: some View {
    Canvas { context, size in
      let w = size.width
      let h = size.height
      // Major ticks sit under each label's cell centre; "0" is the last one
      // and its position is the top of the signal range (0 dBFS = max).
      let majors = (0..<labelCount).map { (Double($0) + 0.5) / Double(labelCount) }
      let zeroFrac = majors[labelCount - 1]
      let redStart = (majors[labelCount - 2] + zeroFrac) / 2
      let litX = w * zeroFrac * Double(min(max(level, 0), 1))

      // Build the full tick set: majors plus three minors between each pair.
      var ticks: [(x: Double, major: Bool)] = []
      for i in 0..<majors.count {
        ticks.append((majors[i], true))
        if i < majors.count - 1 {
          let step = (majors[i + 1] - majors[i]) / 4
          for m in 1...3 { ticks.append((majors[i] + step * Double(m), false)) }
        }
      }

      for tick in ticks {
        let x = w * tick.x
        let th = tick.major ? h : h * 0.5
        let lit = x <= litX + 0.5
        let red = tick.x >= redStart - 0.001
        let color: Color =
          red
          ? (lit ? Theme.burgundy : Theme.burgundy.opacity(0.32))
          : (lit ? Theme.amber : Theme.amber.opacity(0.22))
        var line = Path()
        line.move(to: CGPoint(x: x, y: h))
        line.addLine(to: CGPoint(x: x, y: h - th))
        context.stroke(line, with: .color(color), lineWidth: tick.major ? 1.4 : 1)
      }
    }
  }
}
