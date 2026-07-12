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
    .padding(.vertical, 12)
    .padding(.horizontal, 18)
    .faceplateBackground(radius: Theme.radiusMD)
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
          Task { await player.seek(to: scrubValue) }
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
    let artist = player.currentTrack?.artist
    return VStack(alignment: .leading, spacing: 3) {
      Text(artist ?? " ")
        .font(Theme.mono(10.8, bold: true))
        .kerning(10.8 * 0.1)
        .textCase(.uppercase)
        .foregroundStyle(Theme.labelDim)
        .lineLimit(1)
        .truncationMode(.tail)
        .opacity(artist == nil ? 0 : 1)
        .accessibilityHidden(artist == nil)
      MarqueeText(
        text: player.currentTrack?.title ?? "nothing playing",
        font: Theme.archivo(19.2, .bold),
        color: Theme.ivory)
      stateRow
    }
  }

  private var stateRow: some View {
    let playing = player.status == .playing
    let color = stateColor(playing: playing)
    return HStack(spacing: 7) {
      Circle()
        .fill(color)
        .frame(width: 6, height: 6)
        .shadow(
          color: playing || player.status == .resolving || player.status == .downloading
            || player.status == .decoding ? color : .clear, radius: 3.5)
      Text(statusText)
        .font(Theme.mono(12.2, bold: true))
        .kerning(12.2 * 0.08)
        .textCase(.uppercase)
        .foregroundStyle(stateColor(playing: playing))
        .lineLimit(1)
        .truncationMode(.tail)
      // Download/preload indicator: only present while a download is in
      // flight, so it clears the moment the track finishes downloading.
      if player.isDownloading {
        Rectangle()
          .fill(Theme.line)
          .frame(width: 1, height: 14)
        HStack(spacing: 4) {
          IconView(glyph: .importDown, size: 11)
          if let percent = player.downloadProgress {
            Text("\(Int(percent.rounded()))%")
              .monospacedDigit()
          }
        }
        .foregroundStyle(Theme.labelDim)
        .font(Theme.mono(10.5, bold: true))
      }
    }
  }

  private var statusText: String {
    var parts = [stateTitle]
    if let message = statusLine.message {
      parts.append(message)
    }
    return parts.joined(separator: " · ")
  }

  private var stateTitle: String {
    switch player.status {
    case .idle: return "idle"
    case .resolving: return "resolving"
    case .downloading: return "downloading"
    case .decoding: return "decoding"
    case .playing: return "playing"
    case .paused: return "paused"
    case .failed: return "failed"
    }
  }

  private func stateColor(playing: Bool) -> Color {
    if player.status == .failed || statusLine.isError { return Theme.error }
    if player.status == .resolving || player.status == .downloading || player.status == .decoding {
      return Theme.amber
    }
    if playing || player.isDownloading { return Theme.burgundy }
    return Theme.dim
  }

  // MARK: buttons

  private var transportButtons: some View {
    HStack(spacing: 9) {
      HWButton(glyph: .prev) { Task { await player.prev() } }
        .help("previous track")
      HWButton(glyph: .back) { Task { await player.seek(by: -5) } }
        .help("back 5 seconds")
      HWButton(
        glyph: player.status == .playing ? .pause : .play,
        width: 78,
        prominent: true,
        disabled: player.status == .resolving || player.status == .downloading
          || player.status == .decoding
      ) {
        Task { await player.togglePause() }
      }
      .help("play / pause")
      HWButton(glyph: .fwd) { Task { await player.seek(by: 5) } }
        .help("forward 5 seconds")
      HWButton(glyph: .next) { Task { await player.next() } }
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
      Text("\(Int((player.volume * 100).rounded()))%")
        .font(Theme.mono(11.2, bold: true))
        .monospacedDigit()
        .foregroundStyle(Theme.labelDim)
        .frame(width: 34, alignment: .trailing)
    }
  }
}
