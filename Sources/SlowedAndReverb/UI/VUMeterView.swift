import SwiftUI

/// L/R kick-band meters: 12 segments each, top two run hot (amber + glow).
/// Polls the engine's level snapshot on the render clock while playing.
struct VUMeterView: View {
  @Environment(PlayerModel.self) private var player

  private let barCount = 12

  var body: some View {
    let playing = player.status == .playing
    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playing)) { _ in
      let levels = playing ? player.levels() : (l: Float(0), r: Float(0))
      VStack(spacing: 9) {
        row(label: "L", level: levels.l)
        row(label: "R", level: levels.r)
      }
    }
  }

  private func row(label: String, level: Float) -> some View {
    HStack(spacing: 8) {
      Text(label)
        .font(Theme.mono(11.8, bold: true))
        .foregroundStyle(Theme.label)
        .frame(width: 14, alignment: .leading)
      let lit = Int((level * Float(barCount)).rounded())
      HStack(spacing: 3) {
        ForEach(0..<barCount, id: \.self) { i in
          let on = i < lit
          let hot = on && i >= barCount - 2
          RoundedRectangle(cornerRadius: 1)
            .fill(hot ? Theme.amber : on ? Theme.etch : Theme.meterOff)
            .shadow(color: hot ? Theme.amberGlow : .clear, radius: 3)
        }
      }
      .frame(height: 13)
      .frame(maxWidth: .infinity)
    }
  }
}
