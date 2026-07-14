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
    cardWithActions
      .contentShape(cardShape)
      .onTapGesture(perform: action)
      .focusable()
      .focusEffectDisabled()
      .focused($focused)
      .onKeyPress(.return, action: handleReturn)
      .accessibilityElement(children: .contain)
      .accessibilityLabel(accessibilityLabel)
      .accessibilityAddTraits(.isButton)
      .accessibilityAction { action() }
      .onHover { hovering = $0 && isEnabled }
      .animation(.easeOut(duration: 0.14), value: focused)
  }

  private var cardWithActions: some View {
    cardChrome
      .help(help)
      .overlay(alignment: .topTrailing) {
        actions()
          .padding(7)
      }
  }

  private var cardChrome: some View {
    content()
      .frame(width: 220, alignment: .leading)
      .background(cardBackground)
      .clipShape(cardShape)
      .overlay {
        cardShape.strokeBorder(
          hovering || focused ? Theme.accentRingStrong : Theme.line,
          lineWidth: focused ? 2 : 1)
      }
  }

  private var cardShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
  }

  private var cardBackground: some View {
    LinearGradient(
      colors: [Theme.activeTop, Theme.queueBottom], startPoint: .top, endPoint: .bottom
    )
  }

  private func handleReturn() -> KeyPress.Result {
    action()
    return .handled
  }

}
