import SwiftUI

struct LibrarySongCard: View {
  let song: LibrarySong
  let playAction: () -> Void
  let queueAction: () -> Void
  let removeAction: (() -> Void)?

  var body: some View {
    LibraryCardSurface(
      accessibilityLabel: accessibilityLabel,
      help: "Play \(song.track.title)",
      action: playAction
    ) {
      VStack(alignment: .leading, spacing: 0) {
        LibraryArtwork(track: song.track)
          .frame(width: 160, height: 142)
          .overlay(alignment: .bottomTrailing) {
            if let duration = song.track.duration {
              Text(TimeFormat.clock(duration))
                .font(Theme.mono(9, bold: true))
                .foregroundStyle(Theme.ivory)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                .padding(7)
            }
          }
        VStack(alignment: .leading, spacing: 3) {
          Text(song.track.title)
            .font(Theme.archivo(12, .semiBold))
            .foregroundStyle(Theme.ivory)
            .lineLimit(1)
          Text(song.track.artist ?? "Unknown artist")
            .font(Theme.mono(8.5))
            .foregroundStyle(Theme.etch)
            .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
      }
    } actions: {
      HStack(spacing: 5) {
        Button(action: queueAction) {
          Label("Add \(song.track.title) to queue", systemImage: "text.badge.plus")
            .labelStyle(.iconOnly)
        }
        .help("Add to queue")

        if let removeAction {
          HoldToDeleteButton(
            accessibilityLabel: "Remove \(song.track.title)",
            help: "Hold to remove from library"
          ) {
            removeAction()
          }
        }
      }
      .buttonStyle(.bordered)
      .controlSize(.mini)
    }
  }

  private var accessibilityLabel: String {
    let artist = song.track.artist ?? "Unknown artist"
    let duration = song.track.duration.map { ", duration \(TimeFormat.clock($0))" } ?? ""
    return "\(song.track.title), by \(artist)\(duration)"
  }
}
