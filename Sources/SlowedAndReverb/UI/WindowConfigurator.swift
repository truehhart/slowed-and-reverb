import AppKit
import SwiftUI

/// Finishing touches on the plain (undecorated) console window: window
/// shadow, close/minimize capability for the plate's own traffic lights,
/// and dev-run activation quirks.
struct WindowConfigurator: NSViewRepresentable {
  @Binding var window: NSWindow?

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async {
      // `swift run` executes the bare binary with a .prohibited activation
      // policy: the window can never become key and every click is dropped.
      // The packaged .app is already .regular, making this a no-op there.
      if NSApp.activationPolicy() != .regular {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
      }
      guard let hosted = view.window else { return }
      // the plate's own close/minimize lights need these capabilities
      hosted.styleMask.insert([.closable, .miniaturizable])
      hosted.isOpaque = false
      hosted.backgroundColor = .clear
      hosted.hasShadow = true
      // Dragging is handled by ConsoleView's WindowDragGesture so that
      // pressing a control never doubles as a window drag.
      hosted.isMovableByWindowBackground = false
      hosted.isRestorable = false
      // nothing starts focused (the web console had no initial focus ring)
      hosted.makeFirstResponder(nil)
      hosted.orderFrontRegardless()
      window = hosted
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {}
}
