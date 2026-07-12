import SwiftUI

@main
struct SlowedAndReverbApp: App {
  @State private var player = PlayerModel()
  @State private var updater = UpdaterModel()

  init() {
    Theme.registerFonts()
  }

  var body: some Scene {
    // .plain = fully undecorated (the original was a decorationless
    // transparent Tauri window): no titlebar accommodation, no safe areas,
    // the window is exactly the console's fixed 980×620.
    Window("slowed + reverb", id: "main") {
      ConsoleView()
        .environment(player)
        .environment(updater)
    }
    .windowStyle(.plain)
    .windowResizability(.contentSize)
    .defaultSize(width: 980, height: 620)
  }
}
