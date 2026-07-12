import AppKit
import SwiftUI

/// Brand plate: window traffic lights, the brand logo, the view switcher,
/// GitHub link, and the version tag — with corner screws for flourish.
struct PlateView: View {
  @Binding var tab: ConsoleView.Tab
  let window: NSWindow?

  var body: some View {
    HStack(spacing: 16) {
      lights
      brand
      Spacer(minLength: 0)
      nav
      githubLink
      versionTag
    }
    .padding(.vertical, 12)
    .padding(.horizontal, 28)
    .panelBackground(Theme.plate, Theme.plate2)
    .overlay { screws }
  }

  // MARK: window lights

  private var lights: some View {
    HStack(spacing: 8) {
      LightButton(
        top: rgb(0xFF9A93), bottom: rgb(0xFF5F57), accessibilityLabel: "Close window"
      ) { window?.close() }
      LightButton(
        top: rgb(0xFFD27A), bottom: rgb(0xFEBC2E), accessibilityLabel: "Minimize window"
      ) { window?.miniaturize(nil) }
      // Fixed-size window: zoom would only ruin the layout, so it's inert
      // and greyed out, like a macOS app that can't zoom.
      LightButton(
        top: rgb(0x74E08A), bottom: rgb(0x28C840), accessibilityLabel: "Zoom window",
        enabled: false
      ) {}
    }
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
      .foregroundStyle(Theme.labelDim)
      .fixedSize()
  }

  private var screws: some View {
    HStack {
      screw
      Spacer()
      screw
    }
    .padding(.horizontal, 9)
  }

  private var screw: some View {
    Circle()
      .fill(
        RadialGradient(
          colors: [rgb(0x4A4032), rgb(0x15110B)],
          center: UnitPoint(x: 0.38, y: 0.32), startRadius: 0, endRadius: 5)
      )
      .overlay(Circle().strokeBorder(.black.opacity(0.5), lineWidth: 1))
      .frame(width: 7, height: 7)
  }

  private func rgb(_ value: UInt32) -> Color {
    Color(
      red: Double((value >> 16) & 0xFF) / 255,
      green: Double((value >> 8) & 0xFF) / 255,
      blue: Double(value & 0xFF) / 255)
  }
}

/// One traffic light: crisp rim + tiny gloss, brightens on hover.
private struct LightButton: View {
  let top: Color
  let bottom: Color
  let accessibilityLabel: String
  var enabled = true
  let action: () -> Void

  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      Circle()
        .fill(
          RadialGradient(
            colors: [top, bottom], center: UnitPoint(x: 0.35, y: 0.3),
            startRadius: 0, endRadius: 9)
        )
        .overlay(Circle().strokeBorder(.black.opacity(0.45), lineWidth: 0.5))
        .overlay(alignment: .top) {
          Circle().fill(.white.opacity(0.35)).frame(width: 8, height: 3).blur(radius: 1)
            .padding(.top, 1)
        }
        .frame(width: 12, height: 12)
        .saturation(enabled ? 1 : 0.3)
        .brightness(hovering && enabled ? 0.12 : enabled ? 0 : -0.15)
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .onHover { hovering = $0 }
    .accessibilityLabel(accessibilityLabel)
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
