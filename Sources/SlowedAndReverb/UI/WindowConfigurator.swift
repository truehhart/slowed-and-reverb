import AppKit
import SwiftUI

/// Configures the native traffic lights over the custom console chrome.
struct WindowConfigurator: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async {
      if NSApp.activationPolicy() != .regular {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
      }
      guard let window = view.window else { return }
      window.styleMask.insert([.closable, .miniaturizable, .fullSizeContentView])
      window.styleMask.remove(.resizable)
      window.titlebarAppearsTransparent = true
      window.titleVisibility = .hidden
      window.isOpaque = true
      window.backgroundColor = NSColor(calibratedRed: 0.07, green: 0.05, blue: 0.04, alpha: 1)
      window.hasShadow = true
      window.isMovableByWindowBackground = false
      window.isRestorable = false
      window.makeFirstResponder(nil)
      window.orderFrontRegardless()
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {}
}
