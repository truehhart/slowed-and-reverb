import AppKit
import SwiftUI

/// Integrated app chrome: brand, navigation, links, and version.
struct PlateView: View {
  @Binding var tab: ConsoleView.Tab

  var body: some View {
    HStack(spacing: 16) {
      brand
      Spacer(minLength: 0)
      nav
      githubLink
      versionTag
    }
    .padding(.vertical, 14)
    .padding(.leading, Theme.pad)
    .padding(.trailing, Theme.pad + 8)
    .topChromeBackground()
    .contentShape(Rectangle())
  }

  private var brand: some View {
    Group {
      if let logo = Theme.brandLogo {
        Image(nsImage: logo)
          .resizable()
          .interpolation(.high)
          .aspectRatio(contentMode: .fit)
          .frame(height: 42)
      }
    }
  }

  private var nav: some View {
    HStack(spacing: 6) {
      ForEach(ConsoleView.Tab.allCases, id: \.self) { item in
        SwitchButton(
          title: item.rawValue, isSelected: tab == item, isEnabled: item.enabled
        ) {
          tab = item
        }
        .help(item.enabled ? "" : "coming soon")
      }
    }
    .padding(4)
    .railBackground(depth: 12)
  }

  private var githubLink: some View {
    HoverColorButton(base: Theme.dim, hover: Theme.ivory) {
      NSWorkspace.shared.open(URL(string: "https://github.com/truehhart/slowed-and-reverb")!)
    } label: {
      IconView(glyph: .github, size: 16)
    }
    .help("github.com/truehhart/slowed-and-reverb")
    .accessibilityLabel("Open GitHub")
  }

  private var versionTag: some View {
    Text(AppInfo.version == "dev" ? "dev" : "v\(AppInfo.version)")
      .font(Theme.mono(9.9))
      .kerning(9.9 * 0.16)
      .textCase(.uppercase)
      .foregroundStyle(AppInfo.version == "dev" ? Theme.burgundy : Theme.labelDim)
      .fixedSize()
  }

}

/// A view-switcher tab in the plate's rail.
private struct SwitchButton: View {
  let title: String
  let isSelected: Bool
  let isEnabled: Bool
  let action: () -> Void

  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(Theme.archivo(13.4, .semiBold))
        .kerning(13.4 * 0.04)
        .textCase(.uppercase)
        .padding(.vertical, 9)
        .padding(.horizontal, 15)
    }
    .buttonStyle(
      SwitchButtonStyle(isSelected: isSelected, isEnabled: isEnabled, hovering: hovering)
    )
    .disabled(!isEnabled)
    .onHover { hovering = $0 }
    .accessibilityLabel(title)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

private struct SwitchButtonStyle: ButtonStyle {
  let isSelected: Bool
  let isEnabled: Bool
  let hovering: Bool

  func makeBody(configuration: Configuration) -> some View {
    let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
    return configuration.label
      .foregroundStyle(isSelected ? Theme.ivory : hovering && isEnabled ? Theme.ivory : Theme.dim)
      .background {
        if isSelected {
          shape
            .fill(
              LinearGradient(
                colors: [Theme.activeTop, Theme.activeBottom], startPoint: .top,
                endPoint: .bottom)
            )
            .overlay(shape.strokeBorder(Theme.accentRing, lineWidth: 1))
            .shadow(color: Theme.accentGlow, radius: 5)
        }
      }
      // Whole pill (padding included) is tappable/hoverable, selected or not.
      .contentShape(shape)
      .opacity(isEnabled ? 1 : 0.45)
      .scaleEffect(configuration.isPressed ? 0.96 : 1)
      .animation(.easeOut(duration: 0.15), value: isSelected)
      .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
  }
}

/// Icon-only link that shifts color on hover (the GitHub mark).
private struct HoverColorButton<Label: View>: View {
  let base: Color
  let hover: Color
  let action: () -> Void
  @ViewBuilder let label: () -> Label

  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      label().foregroundStyle(hovering ? hover : base)
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
  }
}
