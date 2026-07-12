import SwiftUI

/// A fader: slim recessed track with a burgundy fill up to the value and a
/// brushed-ivory thumb. Used by the scrubber and the volume control.
struct FaderSlider: View {
  @Binding var value: Double
  let range: ClosedRange<Double>
  var accessibilityLabel = "Slider"
  var accessibilityValueText: String?
  var accessibilityStep: Double?
  /// Called with true when a drag starts and false when it ends, so the
  /// scrubber can defer the actual seek until release.
  var onEditingChanged: (Bool) -> Void = { _ in }

  @State private var dragging = false

  private let trackHeight: CGFloat = 6
  private let thumbSize = CGSize(width: 14, height: 14)

  var body: some View {
    GeometryReader { proxy in
      let width = proxy.size.width
      let span = max(range.upperBound - range.lowerBound, .ulpOfOne)
      let fraction = ((value - range.lowerBound) / span).clamped01()
      let thumbX = fraction * (width - thumbSize.width) + thumbSize.width / 2

      ZStack(alignment: .leading) {
        Capsule()
          .fill(
            Theme.meterOff.shadow(.inner(color: .black.opacity(0.6), radius: 1, y: 1))
          )
          .frame(height: trackHeight)
        Capsule()
          .fill(Theme.burgundy)
          .frame(width: max(0, thumbX), height: trackHeight)
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(
            LinearGradient(
              colors: [Theme.faderTop, Theme.faderBottom], startPoint: .top, endPoint: .bottom)
          )
          .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.4)).frame(height: 1)
              .padding(.horizontal, 2)
          }
          .frame(width: thumbSize.width, height: thumbSize.height)
          .shadow(color: .black.opacity(0.7), radius: 1.5, y: 1)
          .offset(x: thumbX - thumbSize.width / 2)
      }
      .frame(height: proxy.size.height)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { gesture in
            if !dragging {
              dragging = true
              onEditingChanged(true)
            }
            let usable = max(width - thumbSize.width, 1)
            let f = ((gesture.location.x - thumbSize.width / 2) / usable).clamped01()
            value = range.lowerBound + f * span
          }
          .onEnded { _ in
            dragging = false
            onEditingChanged(false)
          }
      )
    }
    .frame(height: thumbSize.height)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityValue(accessibilityValueText ?? defaultAccessibilityValue)
    .accessibilityAdjustableAction { direction in
      let step = accessibilityStep ?? max((range.upperBound - range.lowerBound) / 100, .ulpOfOne)
      let delta = direction == .increment ? step : -step
      onEditingChanged(true)
      value = min(max(value + delta, range.lowerBound), range.upperBound)
      onEditingChanged(false)
    }
  }

  private var defaultAccessibilityValue: String {
    let span = max(range.upperBound - range.lowerBound, .ulpOfOne)
    return "\(Int((((value - range.lowerBound) / span) * 100).rounded())) percent"
  }
}

extension CGFloat {
  fileprivate func clamped01() -> CGFloat { Swift.min(Swift.max(self, 0), 1) }
}

extension Double {
  fileprivate func clamped01() -> Double { Swift.min(Swift.max(self, 0), 1) }
}
