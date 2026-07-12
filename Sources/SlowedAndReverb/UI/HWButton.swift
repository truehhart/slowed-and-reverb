import SwiftUI

/// A transport deck hardware button. `prominent` is the burgundy play/pause;
/// `active` draws the pressed-in accent ring (repeat modes).
struct HWButton: View {
  let glyph: IconView.Glyph
  var width: CGFloat = 56
  var prominent = false
  var active = false
  var badge: String?
  var disabled = false
  var accessibilityLabel: String? = nil
  let action: () -> Void

  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      buttonContent
    }
    .buttonStyle(HWButtonStyle(hovering: hovering, disabled: disabled))
    .disabled(disabled)
    .onHover { hovering = $0 }
    .accessibilityLabel(accessibilityLabel ?? glyph.accessibilityLabel)
    .accessibilityValue(badge ?? "")
  }

  private var buttonContent: some View {
    let shape = RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
    return ZStack {
      if prominent {
        shape
          .fill(
            LinearGradient(
              colors: [Theme.playTop.opacity(0.7), Theme.playBottom.opacity(0.7)],
              startPoint: .top, endPoint: .bottom)
          )
          .overlay(
            shape.strokeBorder(
              LinearGradient(
                stops: [
                  .init(color: .white.opacity(0.098), location: 0),
                  .init(color: .clear, location: 0.35),
                ],
                startPoint: .top, endPoint: .bottom),
              lineWidth: 1)
          )
          .shadow(color: Theme.accentGlow.opacity(0.7), radius: 6, y: 3)
      } else {
        shape
          .fill(
            LinearGradient(
              colors: [Theme.activeTop, Theme.plate2], startPoint: .top, endPoint: .bottom)
          )
          .overlay {
            GrainTexture.tile.resizable(resizingMode: .tile)
              .opacity(0.035)
              .blendMode(.overlay)
              .clipShape(shape)
          }
          .overlay(shape.strokeBorder(active ? Theme.accentRingStrong : Theme.line, lineWidth: 1))
          .overlay(
            shape.strokeBorder(
              LinearGradient(
                stops: [
                  .init(color: Theme.metalHi, location: 0), .init(color: .clear, location: 0.15),
                ],
                startPoint: .top, endPoint: .bottom),
              lineWidth: 1)
          )
          .shadow(color: .black.opacity(0.85), radius: 3, y: 3)
      }
      IconView(glyph: glyph, size: 20)
        .foregroundStyle(prominent ? Theme.ivory : active ? Theme.burgundy : Theme.etch)
        .offset(x: glyph == .play ? 1 : 0)
      if let badge {
        Text(badge)
          .font(Theme.mono(9, bold: true))
          .foregroundStyle(Theme.buttonInk)
          .frame(minWidth: 11)
          .background(RoundedRectangle(cornerRadius: 3).fill(Theme.burgundy))
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
          .padding(.trailing, 8)
          .padding(.bottom, 5)
      }
    }
    .frame(width: width, height: prominent ? 52 : 46)
    .contentShape(shape)
  }
}

private struct HWButtonStyle: ButtonStyle {
  let hovering: Bool
  let disabled: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .brightness(hovering && !disabled ? 0.09 : 0)
      .opacity(disabled ? 0.45 : 1)
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .offset(y: configuration.isPressed ? 1 : 0)
      .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
  }
}
