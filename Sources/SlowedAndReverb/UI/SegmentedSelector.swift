import SwiftUI

/// Recessed rail of equal-width segment buttons (the tone selectors).
struct SegmentedSelector<Value: Hashable>: View {
  let options: [(label: String, value: Value)]
  @Binding var selection: Value

  var body: some View {
    HStack(spacing: 3) {
      ForEach(options, id: \.value) { option in
        SegmentButton(
          label: option.label, isSelected: selection == option.value
        ) {
          selection = option.value
        }
      }
    }
    .padding(3)
    .railBackground(depth: 5)
  }
}

private struct SegmentButton: View {
  let label: String
  let isSelected: Bool
  let action: () -> Void

  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      Text(label)
        .font(Theme.archivo(13.8, .semiBold))
        .kerning(13.8 * 0.02)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(
      SegmentButtonStyle(isSelected: isSelected, hovering: hovering)
    )
    .onHover { hovering = $0 }
    .accessibilityLabel(label)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

private struct SegmentButtonStyle: ButtonStyle {
  let isSelected: Bool
  let hovering: Bool

  func makeBody(configuration: Configuration) -> some View {
    let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
    return configuration.label
      .foregroundStyle(isSelected || hovering ? Theme.ivory : Theme.dim)
      .background {
        if isSelected {
          shape
            .fill(
              LinearGradient(
                colors: [Theme.activeTop, Theme.activeBottom], startPoint: .top,
                endPoint: .bottom)
            )
            .overlay(shape.strokeBorder(Theme.accentRing, lineWidth: 1))
        }
      }
      .contentShape(Rectangle())
      .scaleEffect(configuration.isPressed ? 0.96 : 1)
      .animation(.easeOut(duration: 0.14), value: isSelected)
      .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
  }
}
