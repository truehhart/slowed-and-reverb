import SwiftUI

/// Left rack unit: the two rolling reels, the VU meters, and the amber tape
/// counter (perceived time — real seconds divided by speed).
struct TapeTransportModule: View {
  @Environment(PlayerModel.self) private var player

  var body: some View {
    ModuleBox("tape transport") {
      let playing = player.status == .playing
      HStack {
        Spacer()
        ReelView(period: 3, playing: playing)
        Spacer()
        ReelView(period: 4.5, playing: playing)
        Spacer()
      }
      .padding(.vertical, 4)

      VUMeterView()

      Spacer(minLength: 0)

      Text(TimeFormat.counter(perceivedTime))
        .font(Theme.mono(31.2, bold: true))
        .kerning(31.2 * 0.04)
        .monospacedDigit()
        .foregroundStyle(Theme.amber)
        .shadow(color: Theme.amberGlow, radius: 5)
        .frame(maxWidth: .infinity)
        .padding(13)
        .railBackground(depth: 9)
    }
  }

  private var perceivedTime: TimeInterval {
    let speed = player.speed
    return speed > 0 ? player.currentTime / speed : player.currentTime
  }
}
