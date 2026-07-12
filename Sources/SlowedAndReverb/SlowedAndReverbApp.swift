import SwiftUI

@main
struct SlowedAndReverbApp: App {
  @State private var player = PlayerModel()
  @State private var updater = UpdaterModel()

  init() {
    Theme.registerFonts()
  }

  var body: some Scene {
    Window("slowed + reverb", id: "main") {
      ConsoleView()
        .environment(player)
        .environment(updater)
    }
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentSize)
    .defaultSize(width: 980, height: 640)
  }
}
