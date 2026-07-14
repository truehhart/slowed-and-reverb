import AppKit
import SwiftUI

struct LibraryArtwork: View {
  @Environment(PlayerModel.self) private var player
  @State private var image: NSImage?
  @State private var imageTrackID: String?

  let track: Track?

  var body: some View {
    ZStack {
      fallback
      if let displayedImage {
        Image(nsImage: displayedImage)
          .resizable()
          .scaledToFill()
          .transition(.opacity)
      }
      GrainTexture.tile.resizable(resizingMode: .tile)
        .opacity(0.09)
        .blendMode(.overlay)
    }
    .clipped()
    .task(id: track?.id) {
      guard let track else {
        image = nil
        imageTrackID = nil
        return
      }
      if let cached = LibraryArtworkCache.shared.image(for: track.id) {
        image = cached
        imageTrackID = track.id
        return
      }
      image = nil
      imageTrackID = nil
      guard let loadedImage = await LibraryArtworkCache.shared.load(track, using: player) else {
        return
      }
      guard !Task.isCancelled else { return }
      image = loadedImage
      imageTrackID = track.id
    }
    .animation(.easeOut(duration: 0.2), value: imageTrackID)
    .accessibilityHidden(true)
  }

  private var displayedImage: NSImage? {
    guard let track else { return nil }
    if imageTrackID == track.id { return image }
    return LibraryArtworkCache.shared.image(for: track.id)
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
