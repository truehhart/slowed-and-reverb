import SwiftUI

/// Center rack unit: the speed and reverb knobs plus the tone selectors
/// (reverb space and low-cut). Knobs work in the UI's 0–100 display units;
/// the player model stores 0–1 scalars.
struct EffectRackModule: View {
  @Environment(PlayerModel.self) private var player

  var body: some View {
    @Bindable var player = player
    ModuleBox("effect rack", centeredTitle: true) {
      HStack(spacing: 10) {
        KnobView(
          value: Binding(
            get: { (player.speed * 100).rounded() },
            set: { player.speed = $0 / 100 }),
          range: 50...100, label: "speed"
        )
        .frame(maxWidth: .infinity)
        KnobView(
          value: Binding(
            get: { (player.reverbMix * 100).rounded() },
            set: { player.reverbMix = $0 / 100 }),
          range: 0...100, label: "reverb"
        )
        .frame(maxWidth: .infinity)
      }
      .frame(maxHeight: .infinity)

      VStack(spacing: 6) {
        toneRow("space") {
          SegmentedSelector(
            options: ReverbSpace.allCases.map { ($0.rawValue, $0) },
            selection: $player.reverbSpace)
        }
        toneRow("low cut") {
          SegmentedSelector(
            options: [80.0, 120, 180, 260].map { (String(Int($0)), $0) },
            selection: $player.reverbCutoff)
        }
      }
    }
  }

  private func toneRow(_ title: String, @ViewBuilder control: () -> some View) -> some View {
    HStack(spacing: 10) {
      Text(title)
        .font(Theme.mono(11.8, bold: true))
        .kerning(11.8 * 0.1)
        .textCase(.uppercase)
        .foregroundStyle(Theme.label)
        .frame(width: 64, alignment: .leading)
      control()
    }
  }
}
