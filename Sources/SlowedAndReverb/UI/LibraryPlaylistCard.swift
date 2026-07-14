import SwiftUI

struct LibraryPlaylistCard: View {
  let playlist: LibraryPlaylist
  let action: () -> Void

  var body: some View {
    LibraryCardSurface(
      accessibilityLabel: accessibilityLabel,
      help: "Open \(playlist.title)",
      action: action
    ) {
      VStack(alignment: .leading, spacing: 0) {
        LibraryArtwork(track: playlist.tracks.first)
          .frame(width: 160, height: 142)
          .overlay(alignment: .bottomLeading) {
            Text(songCount)
              .font(Theme.mono(9, bold: true))
              .foregroundStyle(Theme.ivory)
              .padding(.horizontal, 6)
              .padding(.vertical, 4)
              .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 4))
              .padding(7)
          }
        VStack(alignment: .leading, spacing: 4) {
          Text(playlist.title)
            .font(Theme.archivo(12, .semiBold))
            .foregroundStyle(Theme.ivory)
            .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
      }
    } actions: {
      EmptyView()
    }
  }

  private var songCount: String {
    "\(playlist.tracks.count) \(playlist.tracks.count == 1 ? "song" : "songs")"
  }

  private var accessibilityLabel: String {
    "\(playlist.title), \(songCount)"
  }
}
