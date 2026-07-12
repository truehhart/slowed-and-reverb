import AppKit
import SwiftUI

/// One tape reel: densely wound tape pack (fine radial line pairs), machined
/// flange rims, hub, and a glowing burgundy spindle dot. Rolls while playing
/// and holds its angle when paused (like the CSS paused animation).
struct ReelView: View {
  /// Seconds per revolution (the right reel rolls slower).
  let period: TimeInterval
  let playing: Bool

  @State private var roll = ReelRoll()
  private static let size: CGFloat = 78

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playing)) { timeline in
      Image(nsImage: Self.face)
        .rotationEffect(
          .degrees(roll.angle(now: timeline.date, playing: playing, period: period)))
    }
    .overlay(Circle().strokeBorder(Theme.accentGlowSoft, lineWidth: 1).padding(-1))
    .shadow(color: .black.opacity(0.9), radius: 4, y: 3)
    .frame(width: Self.size, height: Self.size)
  }

  /// The full reel drawn once into an explicit 2× bitmap (SwiftUI rasterizes
  /// drawing-handler images at 1×, which turns the fine tape lines into
  /// blurry moiré). All layers are radially symmetric except the sheen,
  /// which is exactly what should appear to roll.
  private static let face: NSImage = {
    let scale = 2
    let pixels = Int(size) * scale
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    if let ctx = NSGraphicsContext.current?.cgContext {
      ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
      drawFace(in: ctx)
    }
    NSGraphicsContext.restoreGraphicsState()
    let image = NSImage(size: NSSize(width: size, height: size))
    image.addRepresentation(rep)
    rep.size = NSSize(width: size, height: size)
    return image
  }()

  private static func drawFace(in ctx: CGContext) {
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let radius = rect.width / 2
    let space = CGColorSpaceCreateDeviceRGB()

    func circle(_ r: CGFloat) -> CGPath {
      CGPath(
        ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2),
        transform: nil)
    }
    func rgba(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
      CGColor(
        srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
    }
    let reelA = rgba(0x50, 0x3E, 0x2A)
    let reelB = rgba(0x1E, 0x16, 0x0D)

    // tape pack: reel-b base + 112 fine reel-a wedges (1.6° each)
    ctx.addPath(circle(radius))
    ctx.setFillColor(reelB)
    ctx.fillPath()
    ctx.setFillColor(reelA)
    var angle = 0.0
    while angle < 360 {
      ctx.move(to: center)
      ctx.addArc(
        center: center, radius: radius, startAngle: angle * .pi / 180,
        endAngle: (angle + 1.6) * .pi / 180, clockwise: false)
      ctx.closePath()
      ctx.fillPath()
      angle += 3.2
    }

    // warm sheen riding the pack, upper-left (its rotation is the visible roll;
    // the bitmap context is unflipped, so "up" is +y here)
    ctx.saveGState()
    ctx.addPath(circle(radius))
    ctx.clip()
    let sheenCenter = CGPoint(x: rect.width * 0.36, y: rect.height * 0.72)
    let sheen = CGGradient(
      colorsSpace: space,
      colors: [rgba(0xF4, 0xBA, 0x5C, 0.24), rgba(0xF4, 0xBA, 0x5C, 0)] as CFArray,
      locations: [0, 1])!
    ctx.drawRadialGradient(
      sheen, startCenter: sheenCenter, startRadius: 0, endCenter: sheenCenter,
      endRadius: radius * 1.0, options: [])
    // deep edge falloff: inset 0 0 20px black
    let edge = CGGradient(
      colorsSpace: space,
      colors: [rgba(0, 0, 0, 0), rgba(0, 0, 0, 0), rgba(0, 0, 0, 0.6)] as CFArray,
      locations: [0, 0.45, 1])!
    ctx.drawRadialGradient(
      edge, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius,
      options: [])
    ctx.restoreGState()

    // machined flange: crisp outer highlight rim + deep inner ring
    ctx.setStrokeColor(rgba(255, 246, 232, 0.16))
    ctx.setLineWidth(2)
    ctx.addPath(circle(radius - 1))
    ctx.strokePath()
    ctx.setStrokeColor(rgba(0, 0, 0, 0.5))
    ctx.setLineWidth(5)
    ctx.addPath(circle(radius - 4.5))
    ctx.strokePath()

    // hub
    let hubRadius = radius * 0.4
    ctx.saveGState()
    ctx.addPath(circle(hubRadius))
    ctx.clip()
    let hubCenter = CGPoint(x: center.x - hubRadius * 0.24, y: center.y + hubRadius * 0.36)
    let hub = CGGradient(
      colorsSpace: space, colors: [rgba(0x3F, 0x34, 0x2A), reelB] as CFArray,
      locations: [0, 1])!
    ctx.drawRadialGradient(
      hub, startCenter: hubCenter, startRadius: 0, endCenter: center,
      endRadius: hubRadius * 1.4, options: [.drawsAfterEndLocation])
    let hubShade = CGGradient(
      colorsSpace: space, colors: [rgba(0, 0, 0, 0), rgba(0, 0, 0, 0.7)] as CFArray,
      locations: [0.55, 1])!
    ctx.drawRadialGradient(
      hubShade, startCenter: center, startRadius: 0, endCenter: center, endRadius: hubRadius,
      options: [])
    ctx.restoreGState()
    ctx.setStrokeColor(rgba(255, 240, 220, 0.1))
    ctx.setLineWidth(1)
    ctx.addPath(circle(hubRadius - 0.5))
    ctx.strokePath()

    // burgundy spindle with glow
    ctx.setShadow(offset: .zero, blur: 8, color: rgba(0xEE, 0x6A, 0x4E, 0.55))
    ctx.setFillColor(rgba(0xEE, 0x6A, 0x4E))
    ctx.addPath(circle(radius * 0.12))
    ctx.fillPath()
  }
}

/// Accumulates rotation only across playing time so pausing freezes the reel
/// angle instead of snapping it back.
private final class ReelRoll {
  private var accumulated: TimeInterval = 0
  private var lastTick: Date?

  func angle(now: Date, playing: Bool, period: TimeInterval) -> Double {
    if playing {
      if let lastTick {
        accumulated += min(max(now.timeIntervalSince(lastTick), 0), 1)
      }
      lastTick = now
    } else {
      lastTick = nil
    }
    return accumulated / period * 360
  }
}
