import SwiftUI

/// The whole tape console: brand plate on top, the active view (player rack /
/// library / settings) in the middle, transport deck pinned at the bottom.
struct ConsoleView: View {
  enum Tab: String, CaseIterable {
    case player, library, settings

    var enabled: Bool { self != .library }
  }

  @Environment(PlayerModel.self) private var player
  @Environment(UpdaterModel.self) private var updater

  @State private var tab: Tab = .player
  @State private var window: NSWindow?
  @State private var statusLine = StatusLine()
  @State private var queueBox = QueueBoxModel()
  @State private var keyMonitor: KeyEventMonitor?

  var body: some View {
    VStack(spacing: Theme.gap) {
      PlateView(tab: $tab, window: window)
      switch tab {
      case .player:
        HStack(alignment: .top, spacing: Theme.gap) {
          TapeTransportModule()
            .frame(width: 270)
          EffectRackModule()
            .frame(maxWidth: .infinity)
          QueueModule(queueBox: queueBox, statusLine: statusLine)
            .frame(width: 280)
        }
        .frame(maxHeight: .infinity)
      case .settings:
        centered { SettingsView(statusLine: statusLine) }
      case .library:
        centered { LibrarySoonView() }
      }
      TransportDeck(statusLine: statusLine)
    }
    .padding(Theme.pad)
    .frame(width: 980, height: 620)
    .background {
      ZStack {
        LinearGradient(
          colors: [Theme.consoleTop, Theme.consoleBottom], startPoint: .top, endPoint: .bottom)
        GrainTexture.tile
          .resizable(resizingMode: .tile)
      }
    }
    .overlay { vignette.allowsHitTesting(false) }
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    // the whole console is the drag region; controls' own gestures win
    .gesture(WindowDragGesture())
    .background(WindowConfigurator(window: $window))
    .environment(\.colorScheme, .dark)
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
  }

  /// Settings/library layout: a single 360pt column, top-centered.
  private func centered(@ViewBuilder _ content: () -> some View) -> some View {
    VStack {
      content()
        .frame(width: 360)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
