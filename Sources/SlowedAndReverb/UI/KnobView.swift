import AppKit
import SwiftUI

/// A rotary knob: etched tick ring, glowing burgundy value arc over a 270°
/// sweep, machined dome with an indicator line, and an editable numeric
/// readout. Drag (with the vertical axis signed by knob side), scroll wheel,
/// and arrow/page/home/end keys all adjust it, matching the web original.
struct KnobView: View {
  @Binding var value: Double
  let range: ClosedRange<Double>
  let label: String

  @State private var dragValue = 0.0
  @State private var lastDrag: CGPoint?
  @State private var hovering = false
  @State private var scrollMonitor: Any?
  @State private var text = ""
  @FocusState private var fieldFocused: Bool

  private let faceSize: CGFloat = 122
  private let sweep = 270.0
  private let dragPixelsPerRange = 240.0

  var body: some View {
    VStack(spacing: 8) {
      face
        .focusable()
        .focusEffectDisabled()
        .gesture(drag)
        .onHover { over in
          hovering = over
          updateScrollMonitor(over)
        }
        .onKeyPress(phases: .down) { press in
          handleKey(press)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(display(value))
        .accessibilityAdjustableAction { direction in
          let delta = direction == .increment ? 1.0 : -1.0
          value = (value + delta).clamped(to: range)
        }
      readout
    }
    .onAppear { text = display(value) }
    .onChange(of: value) { _, now in
      if !fieldFocused { text = display(now) }
    }
    .onDisappear { updateScrollMonitor(false) }
  }

  private var angle: Double {
    (value - range.lowerBound) / (range.upperBound - range.lowerBound) * sweep
  }

  // MARK: face

  private var face: some View {
    ZStack {
      ticks
      arc
      dome
    }
    .frame(width: faceSize, height: faceSize)
    .contentShape(Circle())
  }

  private var ticks: some View {
    Canvas { context, size in
      let center = CGPoint(x: size.width / 2, y: size.height / 2)
      let outer = size.width / 2 - 1
      for step in 0..<11 {
        let degrees = 225.0 + Double(step) * (sweep / 10)
        let radians = (degrees - 90) * .pi / 180
        let isMajor = step == 0 || step == 5 || step == 10
        let length: CGFloat = isMajor ? 9 : 6
        let inner = outer - length
        var path = Path()
        path.move(
          to: CGPoint(x: center.x + cos(radians) * inner, y: center.y + sin(radians) * inner))
        path.addLine(
          to: CGPoint(x: center.x + cos(radians) * outer, y: center.y + sin(radians) * outer))
        context.stroke(
          path, with: .color(Theme.etch.opacity(isMajor ? 0.72 : 0.48)),
          lineWidth: isMajor ? 1.6 : 1.2)
      }
    }
  }

  private var arc: some View {
    return Canvas { context, size in
      let center = CGPoint(x: size.width / 2, y: size.height / 2)
      let outer = size.width * 0.43
      let inner = size.width * 0.355
      let track = ringSlice(
        center: center, inner: inner, outer: outer,
        fromCSSDegrees: 225 + angle, toCSSDegrees: 225 + sweep)
      context.fill(track, with: .color(.black.opacity(0.56)))
      if angle > 0.5 {
        let lit = ringSlice(
          center: center, inner: inner, outer: outer,
          fromCSSDegrees: 225, toCSSDegrees: 225 + angle)
        context.drawLayer { layer in
          layer.addFilter(.shadow(color: Theme.accentGlow, radius: 4))
          layer.fill(lit, with: .color(Theme.burgundyDeep))
          layer.stroke(lit, with: .color(Theme.burgundy.opacity(0.9)), lineWidth: 1.4)
        }
      }
    }
  }

  private var dome: some View {
    let diameter = faceSize * 0.74
    return ZStack {
      outerGrip
      gripGrooves
      Circle()
        .fill(
          RadialGradient(
            stops: [
              .init(color: .white.opacity(0.1), location: 0),
              .init(color: .white.opacity(0.025), location: 0.54),
              .init(color: .clear, location: 0.8),
            ],
            center: UnitPoint(x: 0.42, y: 0.32), startRadius: 0, endRadius: diameter * 0.66)
        )
        .blendMode(.screen)
      texturedCap(diameter: diameter)
      Circle()
        .fill(
          Color.clear
            .shadow(.inner(color: .black.opacity(0.78), radius: 4, y: -3)))
      indicator(diameter: diameter)
    }
    .frame(width: diameter, height: diameter)
    .rotationEffect(.degrees(angle - 135))
    .background {
      Circle()
        .fill(.black.opacity(0.85))
        .blur(radius: 5)
        .offset(y: 6)
        .padding(3)
    }
  }

  private var outerGrip: some View {
    Circle()
      .fill(
        RadialGradient(
          stops: [
            .init(color: Theme.knobMid.opacity(0.8), location: 0),
            .init(color: Theme.knobLow.opacity(0.94), location: 0.66),
            .init(color: .black.opacity(0.98), location: 1),
          ],
          center: UnitPoint(x: 0.44, y: 0.34), startRadius: 0, endRadius: faceSize * 0.46)
      )
      .overlay(Circle().strokeBorder(.black.opacity(0.95), lineWidth: 2))
      .overlay(Circle().strokeBorder(.white.opacity(0.1), lineWidth: 0.8).padding(2.2))
  }

  private var gripGrooves: some View {
    Canvas { context, size in
      let center = CGPoint(x: size.width / 2, y: size.height / 2)
      let outer = size.width * 0.45
      let inner = size.width * 0.385
      for index in 0..<60 {
        let radians = Double(index) * 6 * .pi / 180
        let start = CGPoint(x: center.x + cos(radians) * inner, y: center.y + sin(radians) * inner)
        let end = CGPoint(x: center.x + cos(radians) * outer, y: center.y + sin(radians) * outer)
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(path, with: .color(.black.opacity(0.78)), lineWidth: 1.2)
        context.stroke(path, with: .color(.white.opacity(0.07)), lineWidth: 0.35)
      }
    }
    .clipShape(Circle())
  }

  private func texturedCap(diameter: CGFloat) -> some View {
    let capDiameter = diameter * 0.68
    return ZStack {
      Circle()
        .fill(
          RadialGradient(
            stops: [
              .init(color: Theme.knobHi.opacity(0.58), location: 0),
              .init(color: Theme.knobMid.opacity(0.92), location: 0.56),
              .init(color: Theme.knobLow, location: 1),
            ],
            center: UnitPoint(x: 0.42, y: 0.3), startRadius: 0, endRadius: capDiameter * 0.72))
      grit
      Circle()
        .strokeBorder(.black.opacity(0.92), lineWidth: 2)
        .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 0.7).padding(1.3))
    }
    .frame(width: capDiameter, height: capDiameter)
    .shadow(color: .black.opacity(0.75), radius: 3, y: 2)
  }

  private var grit: some View {
    Canvas { context, size in
      let center = CGPoint(x: size.width / 2, y: size.height / 2)
      let radius = size.width / 2 - 2
      for index in 0..<180 {
        let seed = Double(index)
        let angle = seed * 2.399_963_23
        let distance = sqrt(
          (sin(seed * 12.9898) * 43_758.5453).truncatingRemainder(dividingBy: 1).magnitude)
        let point = CGPoint(
          x: center.x + cos(angle) * distance * radius,
          y: center.y + sin(angle) * distance * radius)
        let speckSize = 0.35 + (seed.truncatingRemainder(dividingBy: 4) * 0.14)
        let color: Color = index.isMultiple(of: 3) ? .black.opacity(0.22) : .white.opacity(0.1)
        context.fill(
          Path(ellipseIn: CGRect(x: point.x, y: point.y, width: speckSize, height: speckSize)),
          with: .color(color))
      }
    }
    .clipShape(Circle())
  }

  private func indicator(diameter: CGFloat) -> some View {
    VStack {
      RoundedRectangle(cornerRadius: 2)
        .fill(
          LinearGradient(
            colors: [Theme.faderTop, Theme.burgundy], startPoint: .top, endPoint: .bottom)
        )
        .frame(width: 3.5, height: 24)
        .shadow(color: Theme.accentGlow, radius: 3)
        .padding(.top, 8)
      Spacer()
    }
    .frame(width: diameter, height: diameter)
  }

  // MARK: readout

  private var readout: some View {
    VStack(spacing: 2) {
      TextField("", text: $text)
        .textFieldStyle(.plain)
        .font(Theme.mono(22, bold: true))
        .monospacedDigit()
        .multilineTextAlignment(.center)
        .foregroundStyle(fieldFocused ? Theme.burgundy : Theme.ivory)
        .frame(width: 22 * 0.61 * 4, height: 26)
        .focused($fieldFocused)
        .accessibilityLabel("\(label) value")
        .onSubmit { commitText() }
        .onChange(of: fieldFocused) { was, now in
          if was, !now { commitText() }
        }
        .onChange(of: text) { _, now in
          // live-apply while typing, but only for complete in-range values
          if let v = Double(now), range.contains(v) { value = v.rounded() }
        }
      Text(label)
        .font(Theme.mono(12.5, bold: true))
        .kerning(12.5 * 0.18)
        .textCase(.uppercase)
        .foregroundStyle(Theme.label)
    }
  }

  private func display(_ v: Double) -> String {
    String(Int(v.rounded()))
  }

  private func commitText() {
    if let v = Double(text) {
      value = v.rounded().clamped(to: range)
    }
    text = display(value)
  }

  // MARK: interactions

  private var drag: some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .local)
      .onChanged { gesture in
        guard let last = lastDrag else {
          lastDrag = gesture.location
          dragValue = value
          return
        }
        // vertical motion counts toward the side of the knob it happens on
        let side: Double = gesture.location.x >= faceSize / 2 ? 1 : -1
        let delta = (gesture.location.x - last.x) + (gesture.location.y - last.y) * side
        let scale = (range.upperBound - range.lowerBound) / dragPixelsPerRange
        dragValue = (dragValue + delta * scale).clamped(to: range)
        value = dragValue.rounded()
        lastDrag = gesture.location
      }
      .onEnded { _ in lastDrag = nil }
  }

  private func updateScrollMonitor(_ install: Bool) {
    if install, scrollMonitor == nil {
      scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
        guard hovering else { return event }
        let step: Double = event.scrollingDeltaY > 0 ? 1 : event.scrollingDeltaY < 0 ? -1 : 0
        if step != 0 { value = (value + step).clamped(to: range) }
        return nil
      }
    } else if !install, let monitor = scrollMonitor {
      NSEvent.removeMonitor(monitor)
      scrollMonitor = nil
    }
  }

  private func handleKey(_ press: KeyPress) -> KeyPress.Result {
    let delta: Double
    switch press.key {
    case .upArrow, .rightArrow: delta = 1
    case .downArrow, .leftArrow: delta = -1
    case .pageUp: delta = 10
    case .pageDown: delta = -10
    case .home: delta = range.lowerBound - value
    case .end: delta = range.upperBound - value
    default: return .ignored
    }
    value = (value + delta).clamped(to: range)
    return .handled
  }

  /// A filled ring slice between two CSS-space angles (0° = up, clockwise).
  private nonisolated func ringSlice(
    center: CGPoint, inner: CGFloat, outer: CGFloat,
    fromCSSDegrees: Double, toCSSDegrees: Double
  ) -> Path {
    let start = Angle.degrees(fromCSSDegrees - 90)
    let end = Angle.degrees(toCSSDegrees - 90)
    var path = Path()
    path.addArc(center: center, radius: outer, startAngle: start, endAngle: end, clockwise: false)
    path.addArc(center: center, radius: inner, startAngle: end, endAngle: start, clockwise: true)
    path.closeSubpath()
    return path
  }
}

extension Double {
  fileprivate func clamped(to range: ClosedRange<Double>) -> Double {
    Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
  }
}
