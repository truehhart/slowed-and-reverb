import AppKit
import SwiftUI

/// The whole tape console: integrated chrome, active workspace, and transport deck.
struct ConsoleView: View {
  enum Tab: String, CaseIterable {
    case player, library, settings

    var enabled: Bool { true }
  }

  @Environment(PlayerModel.self) private var player
  @Environment(UpdaterModel.self) private var updater

  @State private var tab: Tab = .player
  @State private var statusLine = StatusLine()
  @State private var queueBox = QueueBoxModel()
  @State private var libraryModel = LibraryModel()
  @State private var keyMonitor: KeyEventMonitor?

  var body: some View {
    VStack(spacing: 0) {
      PlateView(tab: $tab)
        .frame(height: 70)
      Group {
        switch tab {
        case .player:
          HStack(alignment: .top, spacing: Theme.gap) {
            TapeTransportModule()
              .frame(width: 280)
            EffectRackModule()
              .frame(maxWidth: .infinity)
            QueueModule(queueBox: queueBox, statusLine: statusLine)
              .frame(width: 318)
          }
        case .settings:
          centered { SettingsView(statusLine: statusLine) }
        case .library:
          LibraryView(model: libraryModel, statusLine: statusLine)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .padding(.horizontal, Theme.pad)
      .padding(.top, Theme.gap)
      TransportDeck(statusLine: statusLine)
        .frame(height: 122)
        .padding(.horizontal, Theme.pad)
        .padding(.top, 12)
        .padding(.bottom, Theme.pad)
    }
    .frame(width: 980, height: 640)
    .consoleChassisBackground()
    .gesture(
      WindowDragGesture()
        .simultaneously(with: TapGesture().onEnded { NSApp.keyWindow?.makeFirstResponder(nil) })
    )
    .overlay { vignette.allowsHitTesting(false) }
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .background(WindowConfigurator())
    .environment(\.colorScheme, .dark)
    .task { await refreshLibrary() }
    .onAppear {
      guard keyMonitor == nil else { return }
      keyMonitor = KeyEventMonitor(player: player, queueBox: queueBox, statusLine: statusLine)
    }
    .onDisappear {
      keyMonitor?.uninstall()
      keyMonitor = nil
    }
    .onChange(of: updater.statusText) { _, text in
      if let text { statusLine.show(text) }
    }
    .onChange(of: tab) { _, tab in
      guard tab == .library, !libraryModel.isLoading else { return }
      Task { await refreshLibrary() }
    }
    .onChange(of: player.libraryRevision) { _, _ in
      guard tab == .library else { return }
      Task { await refreshLibrary() }
    }
  }

  private func refreshLibrary() async {
    await libraryModel.load(using: player)
    await preloadLibraryArtwork()
  }

  private func preloadLibraryArtwork() async {
    let tracks: [Track]
    if libraryModel.selectedPlaylist != nil {
      tracks = libraryModel.selectedPlaylistSongs.prefix(6).map(\.track)
    } else if libraryModel.section == .songs {
      tracks = libraryModel.songs.prefix(6).map(\.track)
    } else {
      tracks = libraryModel.playlists.prefix(6).compactMap { $0.tracks.first }
    }

    await withTaskGroup(of: Void.self) { group in
      for track in tracks {
        group.addTask {
          _ = await LibraryArtworkCache.shared.load(track, using: player)
        }
      }
    }
  }

  /// Settings/library layout: a single 360pt column, horizontally centered
  /// and pinned to the top of the shared middle region.
  private func centered(@ViewBuilder _ content: () -> some View) -> some View {
    content()
      .frame(width: 360)
      .frame(maxWidth: .infinity, alignment: .top)
  }

  /// Vignette frame above the rack; matches
  /// `radial-gradient(135% 135% at 50% -10%, transparent 66%, #0006 100%)`.
  private var vignette: some View {
    EllipticalGradient(
      stops: [
        .init(color: .clear, location: 0.66),
        .init(color: .black.opacity(0.38), location: 1),
      ],
      center: UnitPoint(x: 0.5, y: -0.1),
      startRadiusFraction: 0,
      endRadiusFraction: 1.35)
  }
}
