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
  @FocusState private var knobFocused: Bool

  private let faceSize: CGFloat = 132
  private let sweep = 270.0
  private let dragPixelsPerRange = 240.0

  var body: some View {
    VStack(spacing: 14) {
      face
        .focusable()
        .focused($knobFocused)
        .focusEffectDisabled()
        .overlay {
          if knobFocused {
            Circle().strokeBorder(Theme.accentRingStrong, lineWidth: 2)
          }
        }
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

  /// `repeating-conic-gradient(from 215deg, etch 0 1.3deg, transparent 27deg)`
  /// masked to a thin outer ring: tick marks every 27°.
  private var ticks: some View {
    Canvas { context, size in
      let center = CGPoint(x: size.width / 2, y: size.height / 2)
      let outer = size.width / 2 + 2
      var css = 215.0
      while css < 215 + 360 {
        let path = ringSlice(
          center: center, inner: outer * 0.88, outer: outer * 0.96,
          fromCSSDegrees: css, toCSSDegrees: css + 1.3)
        context.fill(path, with: .color(Theme.etch.opacity(0.45)))
        css += 27
      }
    }
    .padding(-2)
  }

  /// Burgundy conic arc from 225° (CSS) across the sweep, dim rail beyond it.
  private var arc: some View {
    let inset: CGFloat = 7
    return Canvas { context, size in
      let center = CGPoint(x: size.width / 2, y: size.height / 2)
      let outer = size.width / 2
      let inner = outer * 0.845
      let track = ringSlice(
        center: center, inner: inner, outer: outer,
        fromCSSDegrees: 225 + angle, toCSSDegrees: 225 + sweep)
      context.fill(track, with: .color(Theme.lineSoft))
      if angle > 0.5 {
        let lit = ringSlice(
          center: center, inner: inner, outer: outer,
          fromCSSDegrees: 225, toCSSDegrees: 225 + angle)
        context.drawLayer { layer in
          layer.addFilter(.shadow(color: Theme.accentGlow, radius: 6))
          layer.fill(lit, with: .color(Theme.burgundy))
        }
      }
    }
    .padding(inset)
  }

  private var dome: some View {
    let diameter = faceSize - 40
    return ZStack {
      Circle()
        .fill(
          RadialGradient(
            stops: [
              .init(color: Theme.knobHi, location: 0),
              .init(color: Theme.knobMid, location: 0.46),
              .init(color: Theme.knobLow, location: 1),
            ],
            center: UnitPoint(x: 0.5, y: 0.34), startRadius: 0, endRadius: diameter * 0.75))
      machining(diameter: diameter)
      // top inner highlight + bottom inner shade
      Circle()
        .fill(
          Color.clear
            .shadow(
              .inner(color: Color(red: 1, green: 0.98, blue: 0.94).opacity(0.18), radius: 1.5, y: 2)
            )
            .shadow(.inner(color: .black.opacity(0.65), radius: 8, y: -8)))
      Circle().strokeBorder(.black.opacity(0.55), lineWidth: 1)
      indicator(diameter: diameter)
      cap(diameter: diameter)
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

  /// Fine concentric grooves: `repeating-radial-gradient(#0002 0 1px, transparent 1px 3px)`.
  private func machining(diameter: CGFloat) -> some View {
    Canvas { context, size in
      let center = CGPoint(x: size.width / 2, y: size.height / 2)
      var r: CGFloat = 3
      while r < size.width / 2 {
        let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        context.stroke(
          Path(ellipseIn: rect), with: .color(.black.opacity(0.1)), lineWidth: 1)
        r += 3
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
        .frame(width: 4, height: 26)
        .shadow(color: Theme.accentGlow, radius: 4)
        .padding(.top, 9)
      Spacer()
    }
    .frame(width: diameter, height: diameter)
  }

  private func cap(diameter: CGFloat) -> some View {
    Circle()
      .fill(
        RadialGradient(
          colors: [Theme.knobMid, Theme.rail],
          center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: diameter * 0.1)
      )
      .overlay {
        Circle().fill(
          Color.clear.shadow(.inner(color: .black.opacity(0.8), radius: 1, y: 1)))
      }
      .padding(diameter * 0.42)
  }

  // MARK: readout

  private var readout: some View {
    VStack(spacing: 3) {
      TextField("", text: $text)
        .textFieldStyle(.plain)
        .font(Theme.mono(24, bold: true))
        .monospacedDigit()
        .multilineTextAlignment(.center)
        .foregroundStyle(fieldFocused ? Theme.burgundy : Theme.ivory)
        .frame(width: 24 * 0.61 * 4, height: 30)
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
