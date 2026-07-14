import SwiftUI

struct LibraryHeaderActionButton: View {
  let title: String
  let systemImage: String
  let action: () -> Void

  @Environment(\.isEnabled) private var isEnabled
  @State private var hovering = false
  @FocusState private var focused: Bool

  init(
    _ title: String, systemImage: String, action: @escaping () -> Void
  ) {
    self.title = title
    self.systemImage = systemImage
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      Label(title, systemImage: systemImage)
        .font(Theme.archivo(10, .semiBold))
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 9)
        .frame(height: 34)
        .background(
          LinearGradient(
            colors: [Theme.activeTop, Theme.activeBottom], startPoint: .top, endPoint: .bottom),
          in: shape
        )
        .overlay {
          shape.strokeBorder(
            focused || hovering ? Theme.accentRingStrong : Theme.line, lineWidth: 1)
        }
    }
    .buttonStyle(.plain)
    .focused($focused)
    .onHover { hovering = $0 && isEnabled }
    .opacity(isEnabled ? 1 : 0.45)
    .accessibilityLabel(title)
  }

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: 7, style: .continuous)
  }

  private var foregroundColor: Color {
    if !isEnabled { return Theme.labelDim }
    return hovering || focused ? Theme.ivory : Theme.etch
  }
}
