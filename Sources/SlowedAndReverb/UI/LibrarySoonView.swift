import SwiftUI

/// Placeholder for the library view (parity with the original's "soon" card).
struct LibrarySoonView: View {
  var body: some View {
    ModuleBox("library", expands: false) {
      Text(
        "A persistent collection — playlists, sorting, storage cap — is coming. "
          + "For now, the \u{201C}up next\u{201D} queue holds your session."
      )
      .font(Theme.archivo(12.5, .medium))
      .foregroundStyle(Theme.dim)
      .lineSpacing(12.5 * 0.5)
      .fixedSize(horizontal: false, vertical: true)
    }
  }
}
