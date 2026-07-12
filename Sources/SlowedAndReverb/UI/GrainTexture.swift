import AppKit
import SwiftUI

/// The console's film-grain overlay: a deterministic 160×160 gray-noise tile,
/// standing in for the original's static feTurbulence data-URI (drawn at 50%
/// opacity over the console gradient).
enum GrainTexture {
  static let tile: Image = Image(nsImage: makeTile())

  private static func makeTile() -> NSImage {
    let size = 160
    var seed: UInt64 = 0x5EED_50DA
    func random() -> UInt64 {
      // SplitMix64: deterministic so the tile is identical every launch.
      seed &+= 0x9E37_79B9_7F4A_7C15
      var z = seed
      z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
      z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
      return z ^ (z >> 31)
    }

    var pixels = [UInt8](repeating: 0, count: size * size * 2)
    for i in 0..<(size * size) {
      let r = random()
      // Two-octave-ish noise: average two samples so the grain isn't pure salt.
      let a = UInt8(truncatingIfNeeded: r)
      let b = UInt8(truncatingIfNeeded: r >> 8)
      let gray = UInt8((UInt16(a) + UInt16(b)) / 2)
      pixels[i * 2] = gray
      // The source SVG rect uses 50% opacity, but fractal noise clusters
      // around mid-gray; uniform noise needs less alpha to read the same.
      pixels[i * 2 + 1] = 96
    }

    let provider = CGDataProvider(data: Data(pixels) as CFData)!
    let cgImage = CGImage(
      width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 16, bytesPerRow: size * 2,
      space: CGColorSpaceCreateDeviceGray(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
  }
}
