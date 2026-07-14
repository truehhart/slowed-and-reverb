import SwiftUI

struct LibraryBackButton: View {
  let action: () -> Void

  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 5) {
        Image(systemName: "chevron.left")
          .font(.system(size: 9, weight: .bold))
        Text("Playlists")
          .font(Theme.archivo(10.5, .semiBold))
      }
      .foregroundStyle(hovering ? Theme.ivory : Theme.etch)
      .padding(.horizontal, 10)
      .frame(height: 34)
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
    .accessibilityLabel("Back to playlists")
  }
}
