import AppKit
import SwiftUI

/// Deterministic, broad tonal variation for the console's aged material.
enum MaterialTexture {
  static let mottle = Image(nsImage: makeTile())

  private static func makeTile() -> NSImage {
    let size = 320
    var seed: UInt64 = 0xC0FF_EE12_7A11
    func random() -> UInt64 {
      seed &+= 0x9E37_79B9_7F4A_7C15
      var value = seed
      value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
      value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
      return value ^ (value >> 31)
    }

    var anchors = [Double]()
    for _ in 0..<81 { anchors.append(Double(random() & 0xFF) / 255) }
    var pixels = [UInt8](repeating: 0, count: size * size * 2)
    for y in 0..<size {
      for x in 0..<size {
        let gridX = Double(x) / Double(size - 1) * 8
        let gridY = Double(y) / Double(size - 1) * 8
        let left = Int(gridX)
        let top = Int(gridY)
        let right = min(left + 1, 8)
        let bottom = min(top + 1, 8)
        let horizontal = gridX - Double(left)
        let vertical = gridY - Double(top)
        let a = anchors[top * 9 + left] * (1 - horizontal) + anchors[top * 9 + right] * horizontal
        let b =
          anchors[bottom * 9 + left] * (1 - horizontal)
          + anchors[bottom * 9 + right] * horizontal
        let value = a * (1 - vertical) + b * vertical
        let index = (y * size + x) * 2
        pixels[index] = UInt8((value * 78 + 88).rounded())
        pixels[index + 1] = 255
      }
    }

    let provider = CGDataProvider(data: Data(pixels) as CFData)!
    let image = CGImage(
      width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 16, bytesPerRow: size * 2,
      space: CGColorSpaceCreateDeviceGray(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    return NSImage(cgImage: image, size: NSSize(width: size, height: size))
  }
}

extension View {
  func consoleChassisBackground(radius: CGFloat = 14) -> some View {
    background {
      let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
      shape
        .fill(
          LinearGradient(
            colors: [Theme.chassisTop, Theme.chassisBottom], startPoint: .top, endPoint: .bottom)
        )
        .overlay {
          MaterialTexture.mottle.resizable(resizingMode: .tile)
            .opacity(Theme.chassisMottleOpacity)
            .blendMode(.softLight)
            .clipShape(shape)
        }
        .overlay {
          GrainTexture.tile.resizable(resizingMode: .tile)
            .opacity(Theme.chassisGrainOpacity)
            .blendMode(.overlay)
            .clipShape(shape)
        }
        .overlay(shape.strokeBorder(Theme.chassisRim, lineWidth: 1))
        .overlay(shape.strokeBorder(.black.opacity(0.7), lineWidth: 1).padding(1))
        .ignoresSafeArea()
    }
  }

  func faceplateBackground(radius: CGFloat = Theme.radiusLG) -> some View {
    background {
      let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
      shape
        .fill(
          LinearGradient(colors: [Theme.panel, Theme.panel2], startPoint: .top, endPoint: .bottom)
        )
        .overlay {
          MaterialTexture.mottle.resizable(resizingMode: .tile)
            .opacity(Theme.faceplateMottleOpacity)
            .blendMode(.softLight)
            .clipShape(shape)
        }
        .overlay {
          GrainTexture.tile.resizable(resizingMode: .tile)
            .opacity(Theme.faceplateGrainOpacity)
            .blendMode(.overlay)
            .clipShape(shape)
        }
        .overlay {
          LinearGradient(
            colors: [.black.opacity(0.22), .clear, .black.opacity(0.28)],
            startPoint: .top, endPoint: .bottom
          ).clipShape(shape)
        }
        .overlay(shape.strokeBorder(Theme.line, lineWidth: 1))
        .overlay(shape.strokeBorder(.black.opacity(0.48), lineWidth: 1).padding(1))
    }
  }

  func recessBackground(radius: CGFloat = Theme.radiusSM, depth: CGFloat = 6) -> some View {
    background {
      let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
      shape
        .fill(Theme.rail.shadow(.inner(color: .black.opacity(0.72), radius: depth / 2, x: 0, y: 2)))
        .overlay {
          GrainTexture.tile.resizable(resizingMode: .tile)
            .opacity(Theme.recessGrainOpacity)
            .blendMode(.overlay)
            .clipShape(shape)
        }
        .overlay(shape.strokeBorder(Theme.line, lineWidth: 1))
        .overlay(shape.strokeBorder(.black.opacity(0.4), lineWidth: 1).padding(1))
    }
  }

  func topChromeBackground() -> some View {
    background {
      Rectangle()
        .fill(
          LinearGradient(
            colors: [Theme.chassisTop.opacity(0.82), Theme.chassisBottom.opacity(0.15)],
            startPoint: .top, endPoint: .bottom)
        )
        .overlay {
          GrainTexture.tile.resizable(resizingMode: .tile)
            .opacity(Theme.chromeGrainOpacity)
            .blendMode(.overlay)
        }
        .overlay(alignment: .bottom) {
          Rectangle().fill(Theme.chromeSeam).frame(height: 1)
            .shadow(color: .black.opacity(0.72), radius: 2, y: 2)
        }
        .ignoresSafeArea(edges: .top)
    }
  }
}
