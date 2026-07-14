import SwiftUI

struct LibrarySearchField: View {
  let placeholder: String
  @Binding var text: String

  @FocusState private var focused: Bool

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(focused ? Theme.burgundy : Theme.labelDim)
      TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.labelDim))
        .textFieldStyle(.plain)
        .font(Theme.archivo(11.5, .medium))
        .foregroundStyle(Theme.ivory)
        .focused($focused)
        .accessibilityLabel(placeholder)
      if !text.isEmpty {
        Button {
          text = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 11))
            .foregroundStyle(Theme.labelDim)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear search")
      }
    }
    .padding(.horizontal, 11)
    .frame(height: 36)
    .railBackground(radius: 7, depth: 5)
    .overlay {
      RoundedRectangle(cornerRadius: 7, style: .continuous)
        .strokeBorder(focused ? Theme.accentRingStrong : .clear, lineWidth: 1)
    }
    .animation(.easeOut(duration: 0.14), value: focused)
  }
}
