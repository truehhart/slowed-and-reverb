import SwiftUI

/// Settings — the storage gauge: cache size readout that ramps amber →
/// burgundy as the cache fills, a 16-segment meter, and a two-step purge
/// with a right-to-left drain animation.
struct SettingsView: View {
  @Environment(PlayerModel.self) private var player
  let statusLine: StatusLine

  @State private var cacheBytes: UInt64 = 0
  @State private var displayBytes: UInt64 = 0
  @State private var litOverride: Int?
  @State private var purgePhase = PurgePhase.idle
  @State private var disarmTask: Task<Void, Never>?
  @State private var purgeTask: Task<Void, Never>?

  private enum PurgePhase {
    case idle, armed, purging, emptied
  }

  /// Bar is full + reddest at 10 GiB; past that the number keeps climbing.
  /// Nothing is enforced — it's a nudge, not a cap.
  private static let cacheCap = 10.0 * 1024 * 1024 * 1024
  private static let segments = 16
  private static let hotFrom = 12  // top quarter reads red

  var body: some View {
    ModuleBox("storage", expands: false) {
      VStack(alignment: .leading, spacing: 16) {
        readout
        meter
        purgeButton
      }
    }
    .task {
      while !Task.isCancelled {
        if purgePhase == .idle || purgePhase == .armed {
          cacheBytes = await player.cacheSize()
          displayBytes = cacheBytes
        }
        try? await Task.sleep(for: .seconds(1))
      }
    }
    .onDisappear {
      disarmTask?.cancel()
      purgeTask?.cancel()
      purgePhase = .idle
    }
  }

  private var fill: Double { min(1, Double(cacheBytes) / Self.cacheCap) }

  private var litCount: Int {
    litOverride ?? min(Self.segments, Int((fill * Double(Self.segments)).rounded(.up)))
  }

  /// Amber → burgundy, biased to stay warm until the back third.
  private var readoutColor: Color {
    let t = pow(fill, 1.4)
    return Color(
      red: (244 + (238 - 244) * t) / 255,
      green: (186 + (106 - 186) * t) / 255,
      blue: (92 + (78 - 92) * t) / 255)
  }

  private var readout: some View {
    let size = TimeFormat.byteSize(displayBytes)
    return HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(size.value)
        .font(Theme.mono(36.8, bold: true))
        .monospacedDigit()
        .foregroundStyle(readoutColor)
        .shadow(color: readoutColor.opacity(0.55), radius: 5.5)
      Text(size.unit)
        .font(Theme.mono(14.4, bold: true))
        .kerning(14.4 * 0.12)
        .textCase(.uppercase)
        .foregroundStyle(Theme.labelDim)
    }
  }

  private var meter: some View {
    HStack(spacing: 3) {
      ForEach(0..<Self.segments, id: \.self) { i in
        let on = i < litCount
        let hot = on && i >= Self.hotFrom
        RoundedRectangle(cornerRadius: 2)
          .fill(hot ? Theme.burgundy : on ? Theme.amber : Theme.meterOff)
          .shadow(color: hot ? Theme.accentGlow : on ? Theme.amberGlow : .clear, radius: 3)
          .frame(height: 20)
          .frame(maxWidth: .infinity)
          .animation(.easeInOut(duration: 0.22), value: on)
          .animation(.easeInOut(duration: 0.22), value: hot)
      }
    }
    .padding(.vertical, 9)
    .padding(.horizontal, 10)
    .railBackground(depth: 7)
  }

  // MARK: purge

  private var purgeTitle: String {
    switch purgePhase {
    case .idle: return "purge cache"
    case .armed: return "tap again to clear"
    case .purging: return "purge cache"
    case .emptied: return "cache cleared"
    }
  }

  private var purgeButton: some View {
    PurgeButtonLabel(
      title: purgeTitle, phase: purgePhaseStyle, disabled: purgePhase == .purging
    ) {
      handlePurgeTap()
    }
  }

  private var purgePhaseStyle: PurgeButtonLabel.Style {
    switch purgePhase {
    case .armed: return .armed
    case .emptied: return .empty
    default: return .normal
    }
  }

  private func handlePurgeTap() {
    switch purgePhase {
    case .idle:
      purgePhase = .armed
      disarmTask?.cancel()
      disarmTask = Task {
        try? await Task.sleep(for: .seconds(2.6))
        if !Task.isCancelled, purgePhase == .armed { purgePhase = .idle }
      }
    case .armed:
      disarmTask?.cancel()
      purgePhase = .purging
      purgeTask = Task { await purge() }
    case .purging, .emptied:
      break
    }
  }

  private func purge() async {
    do {
      try await player.purgeCache()
    } catch {
      purgePhase = .idle
      statusLine.show(String(describing: error), isError: true)
      return
    }
    guard !Task.isCancelled else { return }
    // drain: bars wink out right-to-left while the number eases to zero
    let lit = litCount
    let total = max(0.3, Double(lit) * 0.055)
    let start = Date()
    let startBytes = Double(displayBytes)
    while !Task.isCancelled {
      let k = min(1, Date().timeIntervalSince(start) / total)
      displayBytes = UInt64(startBytes * pow(1 - k, 3))
      litOverride = max(0, lit - Int((Double(lit) * k).rounded(.up)))
      if k >= 1 { break }
      try? await Task.sleep(for: .milliseconds(30))
    }
    guard !Task.isCancelled else { return }
    cacheBytes = 0
    displayBytes = 0
    litOverride = nil
    purgePhase = .emptied
    try? await Task.sleep(for: .seconds(1.5))
    guard !Task.isCancelled else { return }
    purgePhase = .idle
  }
}

/// The purge button chrome: burgundy normally, amber while armed, recessed
/// panel style right after a wipe.
private struct PurgeButtonLabel: View {
  enum Style {
    case normal, armed, empty
  }

  let title: String
  let phase: Style
  let disabled: Bool
  let action: () -> Void

  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(Theme.archivo(12.8, .bold))
        .kerning(12.8 * 0.1)
        .textCase(.uppercase)
        .padding(.vertical, 12)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(PurgeButtonStyle(phase: phase, disabled: disabled, hovering: hovering))
    .disabled(disabled)
    .onHover { hovering = $0 }
    .accessibilityLabel(title)
    .accessibilityHint(phase == .normal ? "Tap once to arm, then tap again to clear the cache" : "")
  }

}

private struct PurgeButtonStyle: ButtonStyle {
  let phase: PurgeButtonLabel.Style
  let disabled: Bool
  let hovering: Bool

  func makeBody(configuration: Configuration) -> some View {
    let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
    return configuration.label
      .foregroundStyle(foreground)
      .background {
        switch phase {
        case .normal:
          shape
            .fill(
              LinearGradient(
                colors: [Theme.burgundy, Theme.burgundyDeep], startPoint: .top,
                endPoint: .bottom)
            )
            .shadow(color: Theme.accentGlow, radius: 4, y: 4)
        case .armed:
          shape.fill(
            LinearGradient(
              colors: [Theme.amber, Color(red: 0.79, green: 0.54, blue: 0.18)],
              startPoint: .top, endPoint: .bottom))
        case .empty:
          shape
            .fill(
              LinearGradient(
                colors: [Theme.activeTop, Theme.activeBottom], startPoint: .top,
                endPoint: .bottom)
            )
            .overlay(shape.strokeBorder(Theme.line, lineWidth: 1))
        }
      }
      .overlay(
        shape.strokeBorder(
          LinearGradient(
            stops: [
              .init(color: phase == .empty ? Theme.metalHi : Theme.buttonHi, location: 0),
              .init(color: .clear, location: 0.2),
            ],
            startPoint: .top, endPoint: .bottom),
          lineWidth: 1)
      )
      .brightness(hovering && !disabled && phase == .normal ? 0.08 : 0)
      .scaleEffect(configuration.isPressed ? 0.96 : 1)
      .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
  }

  private var foreground: Color {
    switch phase {
    case .normal: return Theme.buttonInk
    case .armed: return Color(red: 0.16, green: 0.11, blue: 0.03)
    case .empty: return Theme.labelDim
    }
  }
}
