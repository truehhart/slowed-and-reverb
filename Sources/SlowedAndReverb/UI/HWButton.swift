import SwiftUI

/// A transport deck hardware button. `prominent` is the burgundy play/pause;
/// `active` draws the pressed-in accent ring (repeat modes).
struct HWButton: View {
  let glyph: IconView.Glyph
  var width: CGFloat = 48
  var prominent = false
  var active = false
  var badge: String?
  var accessibilityLabel: String? = nil
  let action: () -> Void

  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      buttonContent
    }
    .buttonStyle(HWButtonStyle(hovering: hovering))
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
              colors: [Theme.burgundy, Theme.burgundyDeep], startPoint: .top, endPoint: .bottom)
          )
          .overlay(
            shape.strokeBorder(
              LinearGradient(
                stops: [
                  .init(color: Theme.buttonHi, location: 0), .init(color: .clear, location: 0.15),
                ],
                startPoint: .top, endPoint: .bottom),
              lineWidth: 1)
          )
          .shadow(color: Theme.accentGlow, radius: 5, y: 4)
      } else {
        shape
          .fill(
            LinearGradient(
              colors: [Theme.activeTop, Theme.plate2], startPoint: .top, endPoint: .bottom)
          )
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
        .foregroundStyle(prominent ? Theme.buttonInk : active ? Theme.burgundy : Theme.etch)
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
    .frame(width: width, height: 44)
    .contentShape(shape)
  }
}

private struct HWButtonStyle: ButtonStyle {
  let hovering: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .brightness(hovering ? 0.09 : 0)
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .offset(y: configuration.isPressed ? 1 : 0)
      .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
  }
}
