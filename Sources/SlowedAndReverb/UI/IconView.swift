import SwiftUI

struct IconView: View {
  enum Glyph: Hashable {
    case prev
    case next
    case play
    case pause
    case back
    case fwd
    case repeatLoop
    case volume
    case mute
    case trash
    case importDown
    case github

    var systemName: String {
      switch self {
      case .prev: return "backward.end.fill"
      case .next: return "forward.end.fill"
      case .play: return "play.fill"
      case .pause: return "pause.fill"
      case .back: return "gobackward.5"
      case .fwd: return "goforward.5"
      case .repeatLoop: return "repeat"
      case .volume: return "speaker.wave.2.fill"
      case .mute: return "speaker.slash.fill"
      case .trash: return "trash.fill"
      case .importDown: return "arrow.down.to.line"
      case .github: return "chevron.left.forwardslash.chevron.right"
      }
    }

    var accessibilityLabel: String {
      switch self {
      case .prev: return "Previous track"
      case .next: return "Next track"
      case .play: return "Play"
      case .pause: return "Pause"
      case .back: return "Seek backward"
      case .fwd: return "Seek forward"
      case .repeatLoop: return "Repeat"
      case .volume: return "Volume"
      case .mute: return "Mute"
      case .trash: return "Clear queue"
      case .importDown: return "Import"
      case .github: return "Open GitHub"
      }
    }
  }

  let glyph: Glyph
  var size: CGFloat = 20

  var body: some View {
    Image(systemName: glyph.systemName)
      .font(.system(size: size, weight: .regular))
      .frame(width: size, height: size)
      .accessibilityLabel(glyph.accessibilityLabel)
  }
}
