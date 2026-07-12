import AppKit
import CoreText
import SwiftUI

/// The tape-console palette, fonts, and metrics, ported 1:1 from the original
/// web UI stylesheet (`:root` custom properties).
enum Theme {
  // MARK: palette

  static let ink = rgb(0x14_0F_0A)
  static let panel = rgb(0x2C_23_19)
  static let panel2 = rgb(0x1F_18_10)
  static let plate = rgb(0x2C_23_19)
  static let plate2 = rgb(0x1F_18_10)
  static let rail = rgb(0x12_0D_09)
  static let ivory = rgb(0xF5_ED_E1)
  static let etch = rgb(0xCE_BF_A9)
  static let burgundy = rgb(0xEE_6A_4E)
  static let burgundyDeep = rgb(0xA9_2D_31)
  static let amber = rgb(0xF4_BA_5C)
  static let dim = rgb(0xCA_BF_AD)
  static let label = rgb(0xD4_C5_A9)
  static let labelDim = rgb(0xA8_9A_83)
  static let line = rgb(0xFF_F0_DC).opacity(0.1)
  static let lineSoft = rgb(0xFF_F0_DC).opacity(0.06)
  static let metalHi = rgb(0xFF_F6_E8).opacity(0.07)
  static let activeTop = rgb(0x3A_30_24)
  static let activeBottom = rgb(0x25_1D_14)
  static let queueTop = rgb(0x22_1A_12)
  static let queueBottom = rgb(0x18_11_09)
  static let queueActiveTop = rgb(0x2A_20_16)
  static let queueActiveBottom = rgb(0x1C_15_0D)
  static let buttonInk = rgb(0x2A_0F_08)
  static let playTop = rgb(0xDD_47_36)
  static let playBottom = rgb(0xB0_2C_28)
  static let buttonHi = Color.white.opacity(0.22)
  static let error = rgb(0xFF_8B_78)
  static let accentRing = rgb(0xEE_6A_4E).opacity(0.45)
  static let accentRingStrong = rgb(0xEE_6A_4E).opacity(0.6)
  static let accentGlow = rgb(0xEE_6A_4E).opacity(0.55)
  static let accentGlowSoft = rgb(0xEE_6A_4E).opacity(0.3)
  static let amberGlow = rgb(0xF4_BA_5C).opacity(0.6)
  static let meterOff = rgb(0xFF_F0_DC).opacity(0.09)
  static let meterHover = rgb(0xFF_F0_DC).opacity(0.28)
  static let reelA = rgb(0x5A_46_30)
  static let reelB = rgb(0x1E_16_0D)
  static let reelCore = rgb(0x3F_34_2A)
  static let knobHi = rgb(0x5E_51_42)
  static let knobMid = rgb(0x30_2A_22)
  static let knobLow = rgb(0x14_10_0C)
  static let faderTop = rgb(0xFF_F2_DD)
  static let faderBottom = rgb(0xCD_BF_A8)

  // MARK: material

  static let chassisTop = rgb(0x29_20_17)
  static let chassisBottom = rgb(0x12_0E_0A)
  static let chassisRim = rgb(0xF7_E9_D4).opacity(0.14)
  static let chassisGrainOpacity = 0.16
  static let chassisMottleOpacity = 0.14
  static let faceplateGrainOpacity = 0.22
  static let faceplateMottleOpacity = 0.2
  static let recessGrainOpacity = 0.1
  static let chromeGrainOpacity = 0.13
  static let chromeSeam = Color.black.opacity(0.72)

  // MARK: metrics

  static let radiusLG: CGFloat = 14
  static let radiusMD: CGFloat = 10
  static let radiusSM: CGFloat = 9
  static let pad: CGFloat = 20
  static let gap: CGFloat = 16

  // MARK: fonts

  enum ArchivoWeight: String {
    case medium = "Archivo-Medium"
    case semiBold = "Archivo-SemiBold"
    case bold = "Archivo-Bold"
  }

  static func archivo(_ size: CGFloat, _ weight: ArchivoWeight) -> Font {
    .custom(weight.rawValue, size: size)
  }

  static func mono(_ size: CGFloat, bold: Bool = false) -> Font {
    .custom(bold ? "SpaceMono-Bold" : "SpaceMono-Regular", size: size)
  }

  /// Register the bundled Archivo / Space Mono faces with Core Text.
  /// Call once before any view renders.
  static func registerFonts() {
    let fonts = [
      "archivo-500", "archivo-600", "archivo-700", "space-mono-400", "space-mono-700",
    ]
    for name in fonts {
      guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else {
        Log.app.error("bundled font missing: \(name, privacy: .public)")
        continue
      }
      CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
  }

  static var brandLogo: NSImage? {
    Bundle.module.url(forResource: "brand-text-light", withExtension: "pdf")
      .flatMap { NSImage(contentsOf: $0) }
  }

  private static func rgb(_ value: UInt32) -> Color {
    Color(
      red: Double((value >> 16) & 0xFF) / 255,
      green: Double((value >> 8) & 0xFF) / 255,
      blue: Double(value & 0xFF) / 255)
  }
}

extension View {
  /// Recessed rail background (nav, segmented selectors, counter, meters).
  func railBackground(radius: CGFloat = Theme.radiusSM, depth: CGFloat = 6) -> some View {
    recessBackground(radius: radius, depth: depth)
  }
}
