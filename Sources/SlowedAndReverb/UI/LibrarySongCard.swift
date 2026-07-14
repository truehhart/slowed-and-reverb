import SwiftUI

struct LibrarySongCard: View {
  let song: LibrarySong
  let playAction: () -> Void
  let queueAction: () -> Void
  let removeAction: (() -> Void)?

  @State private var queueButtonHovering = false

  var body: some View {
    LibraryCardSurface(
      accessibilityLabel: accessibilityLabel,
      help: "Play \(song.track.title)",
      action: playAction
    ) {
      VStack(alignment: .leading, spacing: 0) {
        LibraryArtwork(track: song.track)
          .frame(width: 220, height: 220)
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
          Image(systemName: "text.badge.plus")
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(queueButtonHovering ? Theme.ivory : Theme.labelDim)
            .frame(width: 15, height: 15)
            .padding(.horizontal, 6)
            .frame(height: 27)
            .background(.clear)
            .overlay {
              actionButtonShape.strokeBorder(
                queueButtonHovering ? Theme.accentRingStrong : Theme.lineSoft, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { queueButtonHovering = $0 }
        .accessibilityLabel("Add \(song.track.title) to queue")
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
      .padding(4)
      .background(Theme.ink.opacity(0.82), in: actionTrayShape)
      .overlay {
        actionTrayShape.strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
      }
      .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
    }
  }

  private var actionTrayShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: 9, style: .continuous)
  }

  private var actionButtonShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: 7, style: .continuous)
  }

  private var accessibilityLabel: String {
    let artist = song.track.artist ?? "Unknown artist"
    let duration = song.track.duration.map { ", duration \(TimeFormat.clock($0))" } ?? ""
    return "\(song.track.title), by \(artist)\(duration)"
  }
}
