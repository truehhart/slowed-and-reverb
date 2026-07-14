import SwiftUI

struct LibraryCreatePlaylistButton: View {
  var body: some View {
    Button {
    } label: {
      HStack(spacing: 6) {
        Image(systemName: "plus")
          .font(.system(size: 10, weight: .bold))
        Text("Create Playlist")
          .font(Theme.archivo(10.5, .semiBold))
          .lineLimit(1)
      }
      .foregroundStyle(Theme.labelDim)
      .padding(.horizontal, 10)
      .frame(height: 36)
      .frame(maxWidth: .infinity)
      .background(
        Theme.rail.opacity(0.7), in: RoundedRectangle(cornerRadius: 7, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .strokeBorder(Theme.lineSoft, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
    .disabled(true)
    .focusable(false)
    .opacity(0.62)
    .help("Coming soon")
    .accessibilityLabel("Create Playlist")
    .accessibilityValue("Coming soon")
  }
}
