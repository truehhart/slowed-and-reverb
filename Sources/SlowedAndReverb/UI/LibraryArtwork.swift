import SwiftUI

struct LibraryArtwork: View {
  @Environment(PlayerModel.self) private var player
  @State private var artworkURL: URL?

  let track: Track?

  var body: some View {
    ZStack {
      fallback
      if let artworkURL {
        AsyncImage(url: artworkURL, transaction: Transaction(animation: .easeOut(duration: 0.2))) {
          phase in
          if let image = phase.image {
            image.resizable().scaledToFill()
          }
        }
      }
      GrainTexture.tile.resizable(resizingMode: .tile)
        .opacity(0.09)
        .blendMode(.overlay)
    }
    .clipped()
    .task(id: track?.id) {
      artworkURL = nil
      guard let track else { return }
      let resolvedURL = await player.artworkURL(for: track)
      guard !Task.isCancelled else { return }
      artworkURL = resolvedURL
    }
    .accessibilityHidden(true)
  }

  private var fallback: some View {
    ZStack {
      LinearGradient(
        colors: [Theme.burgundyDeep.opacity(0.78), Theme.panel, Theme.rail],
        startPoint: .topLeading,
        endPoint: .bottomTrailing)
      Circle()
        .fill(Theme.amber.opacity(0.12))
        .frame(width: 126, height: 126)
        .blur(radius: 9)
        .offset(x: 47, y: -37)
      Circle()
        .fill(Theme.burgundy.opacity(0.12))
        .frame(width: 100, height: 100)
        .blur(radius: 10)
        .offset(x: -50, y: 42)
      Image(systemName: "music.note")
        .font(.system(size: 35, weight: .medium))
        .foregroundStyle(Theme.ivory.opacity(0.74))
        .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
    }
  }
}
