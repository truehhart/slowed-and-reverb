import SwiftUI

struct LibraryCardSurface<Content: View, Actions: View>: View {
  let accessibilityLabel: String
  let help: String
  let action: () -> Void
  @ViewBuilder let content: () -> Content
  @ViewBuilder let actions: () -> Actions

  @Environment(\.isEnabled) private var isEnabled
  @State private var hovering = false
  @FocusState private var focused: Bool

  var body: some View {
    ZStack(alignment: .topTrailing) {
      Button(action: action) {
        content()
          .frame(width: 160, alignment: .leading)
          .background(cardBackground)
          .clipShape(cardShape)
          .overlay(
            cardShape.strokeBorder(
              hovering || focused ? Theme.accentRingStrong : Theme.line,
              lineWidth: focused ? 2 : 1)
          )
          .shadow(
            color: hovering || focused ? Theme.accentGlowSoft : .black.opacity(0.62), radius: 5,
            y: 3)
      }
      .buttonStyle(CardButtonStyle())
      .focused($focused)
      .help(help)
      .accessibilityLabel(accessibilityLabel)

      actions()
        .padding(7)
    }
    .onHover { hovering = $0 && isEnabled }
    .animation(.easeOut(duration: 0.14), value: focused)
  }

  private var cardShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
  }

  private var cardBackground: some View {
    LinearGradient(
      colors: [Theme.activeTop, Theme.queueBottom], startPoint: .top, endPoint: .bottom
    )
    .overlay {
      MaterialTexture.mottle.resizable(resizingMode: .tile)
        .opacity(0.12)
        .blendMode(.softLight)
    }
    .overlay {
      GrainTexture.tile.resizable(resizingMode: .tile)
        .opacity(0.08)
        .blendMode(.overlay)
    }
  }

  private struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
      configuration.label
        .scaleEffect(configuration.isPressed ? 0.98 : 1)
        .brightness(configuration.isPressed ? -0.06 : 0)
        .offset(y: configuration.isPressed ? 1 : 0)
        .overlay {
          RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
            .strokeBorder(Theme.burgundy, lineWidth: 2)
            .opacity(configuration.isPressed ? 0.72 : 0)
        }
        .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
  }
}
