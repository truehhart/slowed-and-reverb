import SwiftUI

/// Right rack unit: "up next" — hold-to-clear, import (replace queue), the
/// queue rows, and the add row (a queue-item-shaped input with a plus).
struct QueueModule: View {
  @Environment(PlayerModel.self) private var player
  let queueBox: QueueBoxModel
  let statusLine: StatusLine

  @FocusState private var addFieldFocused: Bool

  var body: some View {
    @Bindable var queueBox = queueBox
    return ModuleBox("up next") {
      HStack(spacing: 6) {
        HoldToDeleteButton(
          enabled: !player.queue.isEmpty,
          accessibilityLabel: "Clear queue",
          help: "Hold to clear the queue"
        ) {
          Task { await player.clear() }
        }
        ImportButton(disabled: queueBox.isSubmitting) {
          Task { await queueBox.submit(.replace, player: player, status: statusLine) }
        }
      }
      .fixedSize()
    } content: {
      ScrollView(.vertical) {
        VStack(spacing: 6) {
          ForEach(Array(player.queue.enumerated()), id: \.offset) { index, track in
            QueueRow(
              number: index + 1,
              title: track.title,
              artist: track.artist,
              duration: track.duration,
              isActive: index == player.index
            ) {
              Task { await player.playIndex(index) }
            }
          }
          addRow
        }
      }
      .scrollIndicators(.never)
    }
  }

  private var addRow: some View {
    @Bindable var queueBox = queueBox
    return HStack(spacing: 10) {
      Text("+")
        .font(Theme.archivo(17.6, .medium))
        .foregroundStyle(Theme.burgundy)
        .frame(width: 12)
        .rotationEffect(.degrees(addFieldFocused ? 90 : 0))
        .animation(.easeInOut(duration: 0.18), value: addFieldFocused)
        .opacity(queueBox.isSubmitting ? 0.65 : 1)
        .modifier(PulseWhile(active: queueBox.isSubmitting))
      TextField(
        "ADD TRACK / PLAYLIST",
        text: $queueBox.urlText
      )
      .textFieldStyle(.plain)
      .font(Theme.archivo(15.7, .medium))
      .foregroundStyle(Theme.ivory)
      .tint(Theme.burgundy)
      .focused($addFieldFocused)
      .onSubmit {
        Task { await queueBox.submit(.add, player: player, status: statusLine) }
      }
    }
    .padding(.vertical, 11)
    .padding(.horizontal, 13)
    .background {
      let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
      shape
        .fill(
          LinearGradient(
            colors: [Theme.queueTop, Theme.queueBottom], startPoint: .leading,
            endPoint: .trailing))
    }
    .modifier(
      AddRowChrome(
        engaged: addFieldFocused || queueBox.isSubmitting, flashPulse: queueBox.flashPulse)
    )
    .contentShape(Rectangle())
    .onTapGesture { addFieldFocused = true }
  }
}

/// Ring + glow for the add row: accent while focused/busy, one-shot flash
/// decay when a track lands, hairline otherwise.
private struct AddRowChrome: ViewModifier {
  let engaged: Bool
  let flashPulse: Int

  @State private var flashing = false

  func body(content: Content) -> some View {
    let accent = engaged || flashing
    content
      .overlay {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(accent ? Theme.accentRingStrong : Theme.line, lineWidth: 1)
      }
      .shadow(color: accent ? Theme.accentGlow : .clear, radius: 7)
      .onChange(of: flashPulse) { _, _ in
        flashing = true
        withAnimation(.easeOut(duration: 0.75)) { flashing = false }
      }
  }
}

/// Opacity pulse for the add row's plus while a link resolves.
private struct PulseWhile: ViewModifier {
  let active: Bool
  @State private var dimmed = false

  func body(content: Content) -> some View {
    content
      .opacity(active && dimmed ? 0.3 : 1)
      .onChange(of: active) { _, now in
        if now {
          withAnimation(.easeInOut(duration: 0.45).repeatForever()) { dimmed = true }
        } else {
          withAnimation(.linear(duration: 0.1)) { dimmed = false }
        }
      }
  }
}

private struct QueueRow: View {
  let number: Int
  let title: String
  let artist: String?
  let duration: TimeInterval?
  let isActive: Bool
  let action: () -> Void

  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        if isActive {
          IconView(glyph: .play, size: 10)
            .foregroundStyle(Theme.ivory)
        } else {
          Color.clear
            .frame(width: 10, height: 10)
        }
        Text(String(number))
          .font(Theme.mono(13.1))
          .monospacedDigit()
          .foregroundStyle(isActive ? Theme.ivory : Theme.dim)
          .frame(minWidth: 18, alignment: .trailing)
        VStack(alignment: .leading, spacing: 2) {
          MarqueeText(
            text: title,
            font: Theme.archivo(15.7, isActive ? .semiBold : .medium),
            color: isActive ? Theme.ivory : Theme.etch,
            moves: isActive || hovering,
            startsImmediately: hovering && !isActive
          )
          if let artist {
            MarqueeText(
              text: artist,
              font: Theme.mono(11.2, bold: isActive),
              color: isActive ? Theme.ivory.opacity(0.72) : Theme.dim,
              moves: isActive || hovering,
              startsImmediately: hovering && !isActive
            )
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Spacer(minLength: 0)
        Text(duration.map(TimeFormat.clock) ?? "--:--")
          .font(Theme.mono(13.1))
          .monospacedDigit()
          .foregroundStyle(isActive ? Theme.ivory : Theme.dim)
          .frame(width: 42, alignment: .trailing)
      }
      .padding(.vertical, 11)
      .padding(.horizontal, 13)
    }
    .buttonStyle(QueueRowButtonStyle(isActive: isActive, hovering: hovering))
    .onHover { hovering = $0 }
    .accessibilityLabel([title, artist].compactMap { $0 }.joined(separator: ", "))
    .accessibilityValue(isActive ? "Playing" : "Queued")
    .accessibilityHint("Play this track")
  }
}

private struct QueueRowButtonStyle: ButtonStyle {
  let isActive: Bool
  let hovering: Bool

  func makeBody(configuration: Configuration) -> some View {
    let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
    return configuration.label
      .foregroundStyle(isActive ? Theme.ivory : Theme.etch)
      .background {
        shape
          .fill(
            LinearGradient(
              colors: isActive
                ? [Theme.queueActiveTop, Theme.burgundy.opacity(0.084)]
                : [Theme.queueTop, Theme.queueBottom],
              startPoint: .leading, endPoint: .trailing))
      }
      .overlay {
        shape.strokeBorder(
          isActive ? Theme.accentRingStrong.opacity(0.7) : hovering ? Theme.meterHover : Theme.line,
          lineWidth: 1)
      }
      .shadow(color: isActive ? Theme.accentGlow.opacity(0.7) : .clear, radius: 7)
      .contentShape(Rectangle())
      .scaleEffect(configuration.isPressed ? 0.98 : 1)
      .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
  }
}

/// Import — replaces the queue with the pasted link's tracks.
private struct ImportButton: View {
  let disabled: Bool
  let action: () -> Void

  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        IconView(glyph: .importDown, size: 13)
        Text("import")
          .font(Theme.mono(10.6, bold: true))
          .kerning(10.6 * 0.14)
          .textCase(.uppercase)
      }
      .padding(.vertical, 5)
      .padding(.horizontal, 9)
    }
    .buttonStyle(ImportButtonStyle(disabled: disabled, hovering: hovering))
    .disabled(disabled)
    .onHover { hovering = $0 }
    .accessibilityLabel("Import")
    .help("import — replaces the queue")
  }
}

private struct ImportButtonStyle: ButtonStyle {
  let disabled: Bool
  let hovering: Bool

  func makeBody(configuration: Configuration) -> some View {
    let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
    return configuration.label
      .foregroundStyle(hovering && !disabled ? Theme.amber : Theme.labelDim)
      .background {
        shape.fill(
          hovering && !disabled
            ? Color(red: 1, green: 0.94, blue: 0.86).opacity(0.03) : .clear)
      }
      .overlay {
        shape.strokeBorder(
          hovering && !disabled ? Theme.amberGlow : Theme.lineSoft, lineWidth: 1)
      }
      .opacity(disabled ? 0.5 : 1)
      .scaleEffect(configuration.isPressed ? 0.96 : 1)
      .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
  }
}
