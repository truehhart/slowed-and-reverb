import SwiftUI

struct LibraryDirectionButton: View {
  @Binding var isAscending: Bool

  @State private var hovering = false

  var body: some View {
    Button {
      isAscending.toggle()
    } label: {
      Image(systemName: isAscending ? "arrow.up" : "arrow.down")
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(hovering ? Theme.ivory : Theme.etch)
        .frame(width: 36, height: 36)
        .background(
          LinearGradient(
            colors: [Theme.activeTop, Theme.activeBottom], startPoint: .top, endPoint: .bottom),
          in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(hovering ? Theme.accentRing : Theme.line, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.6), radius: 2, y: 2)
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .accessibilityLabel(isAscending ? "Sort ascending" : "Sort descending")
  }
}
