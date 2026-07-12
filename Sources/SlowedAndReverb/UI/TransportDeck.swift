import SwiftUI

/// The transport deck pinned under every view: seek row, now-playing title
/// with the state line, hardware transport buttons, and mute + volume.
struct TransportDeck: View {
  @Environment(PlayerModel.self) private var player
  let statusLine: StatusLine

  @State private var scrubValue: Double = 0
  @State private var scrubbing = false

  var body: some View {
    VStack(spacing: 12) {
      seekRow
      HStack(spacing: 16) {
        nowPlaying
          .frame(maxWidth: .infinity, alignment: .leading)
        transportButtons
        volumeCluster
      }
    }
    .padding(.vertical, 14)
    .padding(.horizontal, 18)
    .panelBackground(Theme.plate, Theme.plate2, radius: Theme.radiusMD)
  }

  // MARK: seek

  private var seekRow: some View {
    let speed = max(player.speed, .ulpOfOne)
    let current = scrubbing ? scrubValue : player.currentTime
    return HStack(spacing: 14) {
      Text(TimeFormat.clock(current / speed))
        .font(Theme.mono(13.8))
        .monospacedDigit()
        .foregroundStyle(Theme.dim)
      FaderSlider(
        value: Binding(
          get: { scrubbing ? scrubValue : player.currentTime },
          set: { scrubValue = $0 }),
        range: 0...max(player.duration, 0.1),
        accessibilityLabel: "Playback position",
        accessibilityValueText: TimeFormat.clock(current / speed),
        accessibilityStep: 5
      ) { editing in
        if editing {
          scrubValue = player.currentTime
          scrubbing = true
        } else {
          player.seek(to: scrubValue)
          scrubbing = false
        }
      }
      Text("-" + TimeFormat.clock((player.duration - current) / speed))
        .font(Theme.mono(13.8))
        .monospacedDigit()
        .foregroundStyle(Theme.dim)
    }
  }

  // MARK: now playing + state

  private var nowPlaying: some View {
    VStack(alignment: .leading, spacing: 3) {
      MarqueeText(
        text: player.currentTrack?.title ?? "nothing playing",
        font: Theme.archivo(19.2, .bold),
        color: Theme.ivory)
      stateRow
    }
  }

  private var stateRow: some View {
    let playing = player.status == .playing
    let stateText =
      switch player.status {
      case .playing: "playing"
      case .paused: "paused"
      case .failed: "failed"
      default: "idle"
      }
    return HStack(spacing: 7) {
      Circle()
        .fill(playing ? Theme.burgundy : Theme.dim)
        .frame(width: 6, height: 6)
        .shadow(color: playing ? Theme.burgundy : .clear, radius: 3.5)
      Text(statusText(stateText: stateText))
        .font(Theme.mono(12.2, bold: true))
        .kerning(12.2 * 0.08)
        .textCase(.uppercase)
        .foregroundStyle(stateColor(playing: playing))
        .lineLimit(1)
        .truncationMode(.tail)
    }
  }

  private func statusText(stateText: String) -> String {
    var parts = [stateText]
    if player.isDownloading {
      if let percent = player.downloadProgress {
        parts.append("downloading \(Int(percent.rounded()))%")
      } else {
        parts.append("downloading")
      }
    }
    if let message = statusLine.message {
      parts.append(message)
    }
    return parts.joined(separator: " · ")
  }

  private func stateColor(playing: Bool) -> Color {
    if player.status == .failed || statusLine.isError { return Theme.error }
    if playing || player.isDownloading { return Theme.burgundy }
    return Theme.dim
  }

  // MARK: buttons

  private var transportButtons: some View {
    HStack(spacing: 9) {
      HWButton(glyph: .prev) { Task { await player.skipPrev() } }
        .help("previous track")
      HWButton(glyph: .back) { player.seek(by: -5) }
        .help("back 5 seconds")
      HWButton(
        glyph: player.status == .playing ? .pause : .play, width: 62, prominent: true
      ) {
        Task { await player.togglePause() }
      }
      .help("play / pause")
      HWButton(glyph: .fwd) { player.seek(by: 5) }
        .help("forward 5 seconds")
      HWButton(glyph: .next) { Task { await player.skipNext() } }
        .help("next track")
      HWButton(
        glyph: .repeatLoop, active: player.repeatMode != .off,
        badge: player.repeatMode == .one ? "1" : nil
      ) {
        player.toggleRepeat()
      }
      .help("repeat \(String(describing: player.repeatMode))")
      .accessibilityValue(String(describing: player.repeatMode))
      .accessibilityAddTraits(player.repeatMode == .off ? [] : .isSelected)
    }
  }

  private var volumeCluster: some View {
    @Bindable var player = player
    return HStack(spacing: 8) {
      HWButton(
        glyph: player.isMuted ? .mute : .volume,
        width: 40,
        accessibilityLabel: player.isMuted ? "Unmute" : "Mute"
      ) {
        player.toggleMute()
      }
      .help("mute")
      FaderSlider(
        value: $player.volume,
        range: 0...1,
        accessibilityLabel: "Volume",
        accessibilityValueText: "\(Int((player.volume * 100).rounded())) percent",
        accessibilityStep: 0.05
      )
      .frame(width: 96)
    }
  }
}
